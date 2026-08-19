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
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.io.File

/**
 * Long-running foreground Service that:
 *  1. Extracts ABI-matched glibc deps from APK assets (arm64-v8a or armeabi-v7a).
 *  2. Stages ld-linux + canon-sidecar + libEDSDK into filesDir (exec-able).
 *  3. Opens the Canon USB device in Java and fork+execs the sidecar so the
 *     usbfs fd is inherited (ProcessBuilder would close it).
 *  4. Tails logs and restarts on unexpected exit.
 *
 * The native process is **not** started until [UsbManager.openDevice] yields a
 * file descriptor — launching without it crash-loops EDSDK and surfaces
 * "Crashed — restart app" on the splash Device Status row.
 *
 * Flutter [LocalCameraService] connects to http://127.0.0.1:8791.
 */
class CanonSidecarService : Service() {
    companion object {
        private const val TAG = "CanonSidecar"
        private const val NOTIF_CHANNEL_ID = "canon_sidecar"
        private const val NOTIF_ID = 1001

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

    private var permissionGranted = false
    private var sidecarAbi: String? = null
    private var usbDevice: UsbDevice? = null
    private var usbConnection: UsbDeviceConnection? = null

    @Volatile private var runtimeReady = false

    private val runtime =
        CanonSidecarRuntime(
            sidecarDir = { sidecarDir() },
            ensureUsbOpen = { ensureUsbOpen() },
            usbFd = { usbFdOrMinusOne() },
            usbPath = { usbDevice?.deviceName },
            refreshPermission = {
                if (!permissionGranted) {
                    permissionGranted = CanonUsbPermissionManager.hasGrantedPermission(this)
                }
                permissionGranted
            },
            onState = { state = it },
        )

    private val permissionReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) {
                if (intent.action != CanonUsbPermissionManager.ACTION_CANON_PERMISSION_GRANTED) {
                    return
                }
                permissionGranted = true
                ensureUsbOpen()
                onUsbPermissionGranted()
            }
        }

    private val usbHotplugReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent,
            ) {
                when (intent.action) {
                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> onUsbDeviceAttached()
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> onUsbDeviceDetached(intent)
                }
            }
        }

    override fun onCreate() {
        super.onCreate()
        sidecarAbi = CanonSidecarAbi.resolved()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        registerPermissionReceiver()
        registerUsbHotplugReceiver()
        Thread({
            extractAndStage()
            runtimeReady = true
            // USB permission dialog must run from a visible Activity — MainActivity
            // requests on resume. Requesting here races FCM / notification prompts
            // and can flash-dismiss the Canon allow dialog on first launch.
            permissionGranted = CanonUsbPermissionManager.hasGrantedPermission(this)
            if (permissionGranted) {
                ensureUsbOpen()
                runtime.launch(sidecarAbi)
            } else {
                state = "waiting_usb"
            }
        }, "canon-stage").start()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (runtimeReady && runtime.pid <= 0) runtime.launch(sidecarAbi)
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(permissionReceiver)
        } catch (_: Exception) {
        }
        try {
            unregisterReceiver(usbHotplugReceiver)
        } catch (_: Exception) {
        }
        CanonUsbPermissionManager.unregister(this)
        runtime.stop()
        closeUsbConnection()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun onUsbPermissionGranted() {
        val hasFd = usbFdOrMinusOne() >= 0
        if (runtime.pid > 0 && hasFd && !runtime.hasUsbFd) {
            Log.i(TAG, "Canon USB fd ready — restarting sidecar so EDSDK can inherit it")
            runtime.stop()
            runtime.launchAfterUsbReady(sidecarAbi)
            return
        }
        if (runtime.pid > 0) {
            Log.i(TAG, "Canon USB permission granted — sidecar already running")
            return
        }
        Log.i(TAG, "Canon USB permission granted — launching sidecar")
        runtime.launchAfterUsbReady(sidecarAbi)
    }

    private fun onUsbDeviceAttached() {
        Log.i(TAG, "USB device attached — requesting Canon permission / launch")
        permissionGranted = CanonUsbPermissionManager.requestPermissionIfNeeded(this)
        ensureUsbOpen()
        if (runtimeReady && runtime.pid <= 0) {
            runtime.launchAfterUsbReady(sidecarAbi)
        }
    }

    private fun onUsbDeviceDetached(intent: Intent) {
        val device =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
        if (device == null || !CanonUsbPermissionManager.isCanonDslr(device)) return
        Log.i(TAG, "Canon USB detached — stopping sidecar until reattached")
        runtime.stop()
        closeUsbConnection()
        permissionGranted = false
        state = "waiting_usb"
    }

    private fun extractAndStage() {
        val abi = sidecarAbi ?: return
        val destDir = sidecarDir()
        CanonSidecarAssets.extractGlibcDeps(this, abi, destDir)
        CanonSidecarAssets.stageExecutables(
            File(applicationInfo.nativeLibraryDir),
            destDir,
            abi,
        )
        CanonSidecarAssets.makeRuntimeExecutable(destDir)
    }

    private fun registerPermissionReceiver() {
        val filter = IntentFilter(CanonUsbPermissionManager.ACTION_CANON_PERMISSION_GRANTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(permissionReceiver, filter)
        }
    }

    private fun registerUsbHotplugReceiver() {
        val filter =
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbHotplugReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(usbHotplugReceiver, filter)
        }
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
        } catch (e: Exception) {
            Log.w(TAG, "close USB connection: ${e.message}")
        }
        usbConnection = null
        usbDevice = null
    }

    private fun usbFdOrMinusOne(): Int {
        val fd = usbConnection?.fileDescriptor ?: return -1
        return if (fd >= 0) fd else -1
    }

    private fun sidecarDir(): File = CanonSidecarAssets.sidecarDir(filesDir)

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel =
            NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Camera Service",
                NotificationManager.IMPORTANCE_MIN,
            ).apply { setShowBadge(false) }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIF_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        return builder
            .setContentTitle("Camera ready")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
    }
}
