package com.srisarani.fotozenai.canon

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.InputStream

/**
 * Long-running foreground Service that:
 *  1. Extracts ABI-matched glibc deps from APK assets (arm64-v8a or armeabi-v7a).
 *  2. Stages ld-linux + canon-sidecar + libEDSDK into filesDir (exec-able).
 *  3. Opens the Canon USB device in Java and fork+execs the sidecar so the
 *     usbfs fd is inherited (ProcessBuilder would close it).
 *  4. Tails logs and restarts on unexpected exit.
 *
 * Flutter [LocalCameraService] connects to http://127.0.0.1:8791.
 */
class CanonSidecarService : Service() {

    companion object {
        private const val TAG              = "CanonSidecar"
        private const val NOTIF_CHANNEL_ID = "canon_sidecar"
        private const val NOTIF_ID         = 1001
        private const val ASSET_DIR        = "canon_sidecar"
        private const val MAX_RESTARTS     = 10
        private const val HOOK_ASSET_VER   = "3"

        /** Sidecar lifecycle state readable from [CanonSidecarStatusMethodChannel]. */
        @Volatile var state: String = "idle"
            private set

        fun start(context: Context) {
            val abi = CanonSidecarAbi.resolved()
            if (abi == null) {
                Log.w(
                    TAG,
                    "Skipping sidecar; no ARM ABI (${Build.SUPPORTED_ABIS.joinToString()})",
                )
                state = "unsupported_abi"
                return
            }
            Log.i(TAG, "Starting sidecar service for ABI $abi")
            val intent = Intent(context, CanonSidecarService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CanonSidecarService::class.java))
        }
    }

    private var sidecarPid = 0
    private var stdoutPfd: ParcelFileDescriptor? = null
    private var logThread: Thread? = null
    private var watchThread: Thread? = null
    private var restartCount = 0
    private var permissionGranted = false
    private var sidecarAbi: String? = null
    private var usbDevice: UsbDevice? = null
    private var usbConnection: UsbDeviceConnection? = null
    @Volatile private var sidecarHasUsbFd = false
    @Volatile private var spawnEpoch = 0
    @Volatile private var runtimeReady = false

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != CanonUsbPermissionManager.ACTION_CANON_PERMISSION_GRANTED) {
                return
            }
            permissionGranted = true
            ensureUsbOpen()
            val hasFd = usbFdOrMinusOne() >= 0
            if (sidecarPid > 0 && hasFd && !sidecarHasUsbFd) {
                Log.i(TAG, "Canon USB fd ready — restarting sidecar so EDSDK can inherit it")
                stopSidecar()
                launchSidecar()
                return
            }
            if (sidecarPid > 0) {
                Log.i(TAG, "Canon USB permission granted — sidecar already running")
                return
            }
            Log.i(TAG, "Canon USB permission granted — launching sidecar")
            launchSidecar()
        }
    }

    override fun onCreate() {
        super.onCreate()
        sidecarAbi = CanonSidecarAbi.resolved()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                permissionReceiver,
                IntentFilter(CanonUsbPermissionManager.ACTION_CANON_PERMISSION_GRANTED),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            registerReceiver(
                permissionReceiver,
                IntentFilter(CanonUsbPermissionManager.ACTION_CANON_PERMISSION_GRANTED),
            )
        }

        Thread({
            extractAssets()
            stageExecutables()
            makeRuntimeExecutable(sidecarDir())
            runtimeReady = true
            permissionGranted = CanonUsbPermissionManager.requestPermissionIfNeeded(this)
            ensureUsbOpen()
            launchSidecar()
        }, "canon-stage").start()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (runtimeReady && sidecarPid <= 0) launchSidecar()
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterReceiver(permissionReceiver)
        CanonUsbPermissionManager.unregister(this)
        stopSidecar()
        closeUsbConnection()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Extracts glibc dependency libraries from APK assets to filesDir so they
     * are readable at runtime. Executables are copied in [stageExecutables].
     */
    private fun extractAssets() {
        val abi = sidecarAbi ?: return
        val destDir = sidecarDir()
        val marker = File(destDir, ".abi")
        val hookVer = File(destDir, ".hookver")
        if (marker.exists() &&
            marker.readText().trim() == abi &&
            hookVer.exists() &&
            hookVer.readText().trim() == HOOK_ASSET_VER &&
            File(destDir, "libc.so.6").let { it.exists() && it.length() > 0 } &&
            File(destDir, "libudev.so.1").let { it.exists() && it.length() > 0 } &&
            File(destDir, CanonSidecarAbi.USB_HOOK_SO).let { it.exists() && it.length() > 0 }
        ) {
            Log.d(TAG, "Glibc assets already extracted for $abi at $destDir")
            return
        }

        Log.i(TAG, "Extracting glibc assets for $abi to $destDir")
        destDir.deleteRecursively()
        destDir.mkdirs()
        val assetPath = "$ASSET_DIR/$abi"
        val assetFiles = assets.list(assetPath) ?: emptyArray()
        if (assetFiles.isEmpty()) {
            Log.e(TAG, "No sidecar glibc assets at $assetPath")
            return
        }
        for (name in assetFiles) {
            val dest = File(destDir, name)
            assets.open("$assetPath/$name").use { src ->
                dest.outputStream().use { out -> src.copyTo(out) }
            }
        }
        marker.writeText(abi)
        hookVer.writeText(HOOK_ASSET_VER)
        Log.i(TAG, "Extracted ${assetFiles.size} glibc dependency files for $abi")
    }

    /** Copies JNI sidecar binaries into filesDir so they are exec'able. */
    private fun stageExecutables() {
        val abi = sidecarAbi ?: return
        val nativeDir = File(applicationInfo.nativeLibraryDir)
        val destDir = sidecarDir()
        destDir.mkdirs()
        val copies = listOf(
            File(nativeDir, CanonSidecarAbi.interpreterSoName(abi)) to
                File(destDir, CanonSidecarAbi.interpreterRuntimeName(abi)),
            File(nativeDir, CanonSidecarAbi.BINARY_SO) to
                File(destDir, CanonSidecarAbi.BINARY_RUNTIME),
            File(nativeDir, CanonSidecarAbi.EDSDK_SO) to
                File(destDir, CanonSidecarAbi.EDSDK_SO),
        )
        for ((src, dest) in copies) {
            if (!src.exists()) {
                Log.e(TAG, "Missing JNI lib ${src.name} in ${nativeDir.absolutePath}")
                continue
            }
            src.copyTo(dest, overwrite = true)
            dest.setReadable(true, false)
            dest.setExecutable(true, false)
        }
        makeRuntimeExecutable(destDir)
    }

    /** Android 10+ will not mmap a 0600 file as PROT_EXEC — glibc .so files need +x. */
    private fun makeRuntimeExecutable(dir: File) {
        dir.listFiles()?.forEach { file ->
            if (file.isFile) {
                file.setReadable(true, false)
                file.setExecutable(true, false)
            }
        }
    }

    private fun launchSidecar() {
        if (sidecarPid > 0) return
        if (restartCount >= MAX_RESTARTS) {
            Log.e(TAG, "Max restarts ($MAX_RESTARTS) reached — giving up")
            state = "max_restarts"
            return
        }

        val abi = sidecarAbi
        if (abi == null) {
            Log.e(TAG, "Sidecar ABI unresolved")
            state = "unsupported_abi"
            return
        }

        val glibcDir = sidecarDir()
        val interpreter = File(glibcDir, CanonSidecarAbi.interpreterRuntimeName(abi))
        val binary = File(glibcDir, CanonSidecarAbi.BINARY_RUNTIME)

        if (!interpreter.exists() || !binary.exists()) {
            Log.e(
                TAG,
                "Sidecar runtime missing in ${glibcDir.absolutePath} " +
                    "(need ${interpreter.name} and ${binary.name})",
            )
            state = "crashed"
            return
        }
        interpreter.setExecutable(true, false)
        binary.setExecutable(true, false)
        makeRuntimeExecutable(glibcDir)

        if (!permissionGranted) {
            permissionGranted = CanonUsbPermissionManager.hasGrantedPermission(this)
        }
        ensureUsbOpen()

        val usbFd = usbFdOrMinusOne()
        val usbPath = usbDevice?.deviceName
        val hook = File(glibcDir, CanonSidecarAbi.USB_HOOK_SO)
        val preload = if (hook.exists()) hook.absolutePath else ""
        if (usbFd < 0) {
            Log.w(
                TAG,
                "No USB file descriptor yet — EDSDK cannot open usbfs until permission + openDevice",
            )
        }

        Log.i(
            TAG,
            "Starting canon-sidecar $abi (attempt ${restartCount + 1}) " +
                "usbPermission=$permissionGranted usbFd=$usbFd path=$usbPath",
        )

        try {
            val epoch = ++spawnEpoch
            val spawned = CanonSidecarSpawner.spawn(
                interpreter = interpreter.absolutePath,
                args = buildList {
                    add("--library-path")
                    add(glibcDir.absolutePath)
                    if (preload.isNotEmpty()) {
                        add("--preload")
                        add(preload)
                    }
                    add(binary.absolutePath)
                }.toTypedArray(),
                cwd = glibcDir.absolutePath,
                preload = preload,
                usbFd = usbFd,
                usbPath = usbPath,
            )
            sidecarPid = spawned.pid
            sidecarHasUsbFd = usbFd >= 0
            restartCount++
            state = "running"

            stdoutPfd?.close()
            stdoutPfd = ParcelFileDescriptor.adoptFd(spawned.stdoutFd)
            logThread?.interrupt()
            logThread = Thread({
                val fd = stdoutPfd?.fileDescriptor ?: return@Thread
                tailLog(FileInputStream(fd))
            }, "canon-log").also { it.start() }

            watchThread = Thread({
                val code = CanonSidecarSpawner.waitPid(spawned.pid)
                if (epoch != spawnEpoch) {
                    return@Thread
                }
                sidecarPid = 0
                sidecarHasUsbFd = false
                state = if (restartCount >= MAX_RESTARTS) "max_restarts" else "crashed"
                Log.w(TAG, "canon-sidecar exited with code $code — restarting in 3 s")
                try {
                    Thread.sleep(3_000)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@Thread
                }
                if (epoch != spawnEpoch) {
                    return@Thread
                }
                launchSidecar()
            }, "canon-watch").also { it.isDaemon = true; it.start() }
        } catch (e: Exception) {
            state = "crashed"
            sidecarPid = 0
            sidecarHasUsbFd = false
            Log.e(TAG, "Failed to exec canon-sidecar: ${e.message}", e)
        }
    }

    private fun stopSidecar() {
        spawnEpoch++
        val pid = sidecarPid
        sidecarPid = 0
        sidecarHasUsbFd = false
        if (pid > 0) {
            try {
                CanonSidecarSpawner.kill(pid)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to kill sidecar pid=$pid: ${e.message}")
            }
        }
        try {
            stdoutPfd?.close()
        } catch (_: Exception) {
        }
        stdoutPfd = null
        logThread?.interrupt()
        logThread = null
        watchThread = null
    }

    private fun ensureUsbOpen() {
        if (usbConnection != null && usbDevice != null && usbFdOrMinusOne() >= 0) {
            return
        }
        closeUsbConnection()
        val opened = CanonUsbPermissionManager.openCanonConnection(this) ?: return
        usbDevice = opened.first
        usbConnection = opened.second
    }

    private fun closeUsbConnection() {
        try {
            usbConnection?.close()
        } catch (_: Exception) {
        }
        usbConnection = null
        usbDevice = null
    }

    private fun usbFdOrMinusOne(): Int {
        val fd = usbConnection?.fileDescriptor ?: return -1
        return if (fd >= 0) fd else -1
    }

    private fun tailLog(stream: InputStream) {
        try {
            stream.bufferedReader().forEachLine { line ->
                Log.i(TAG, line)
            }
        } catch (_: Exception) {}
    }

    private fun sidecarDir(): File = File(filesDir, ASSET_DIR)

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Camera Service",
                NotificationManager.IMPORTANCE_MIN,
            ).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("Camera ready")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
    }
}
