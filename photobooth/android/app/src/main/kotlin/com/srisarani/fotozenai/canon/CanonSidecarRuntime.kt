package com.srisarani.fotozenai.canon

import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.InputStream

/** Forks, tails, and restarts the native Canon sidecar process. */
internal class CanonSidecarRuntime(
    private val sidecarDir: () -> File,
    private val ensureUsbOpen: () -> Unit,
    private val usbFd: () -> Int,
    private val usbPath: () -> String?,
    private val refreshPermission: () -> Boolean,
    private val onState: (String) -> Unit,
) {
    @Volatile
    var pid: Int = 0
        private set

    @Volatile
    var hasUsbFd: Boolean = false
        private set

    private var lastAbi: String? = null
    private var stdoutPfd: ParcelFileDescriptor? = null
    private var logThread: Thread? = null
    private var watchThread: Thread? = null
    private var restartCount = 0

    @Volatile
    private var spawnEpoch = 0

    fun launch(abi: String?) {
        lastAbi = abi ?: lastAbi
        val plan = buildLaunchPlan(lastAbi) ?: return
        spawnPlan(plan)
    }

    fun stop() {
        spawnEpoch++
        val runningPid = pid
        pid = 0
        hasUsbFd = false
        if (runningPid > 0) {
            try {
                CanonSidecarSpawner.kill(runningPid)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to kill sidecar pid=$runningPid: ${e.message}")
            }
        }
        closeStdoutQuietly()
        logThread?.interrupt()
        logThread = null
        watchThread = null
    }

    private data class LaunchPlan(
        val abi: String,
        val glibcDir: File,
        val interpreter: File,
        val binary: File,
    )

    private fun buildLaunchPlan(abi: String?): LaunchPlan? {
        if (pid > 0) return null
        if (restartCount >= MAX_RESTARTS) {
            Log.e(TAG, "Max restarts ($MAX_RESTARTS) reached — giving up")
            onState("max_restarts")
            return null
        }
        if (abi == null) {
            Log.e(TAG, "Sidecar ABI unresolved")
            onState("unsupported_abi")
            return null
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
            onState("crashed")
            return null
        }
        return LaunchPlan(abi, glibcDir, interpreter, binary)
    }

    private fun spawnPlan(plan: LaunchPlan) {
        plan.interpreter.setExecutable(true, false)
        plan.binary.setExecutable(true, false)
        CanonSidecarAssets.makeRuntimeExecutable(plan.glibcDir)
        val permissionGranted = refreshPermission()
        ensureUsbOpen()

        val fd = usbFd()
        val path = usbPath()
        val hook = File(plan.glibcDir, CanonSidecarAbi.USB_HOOK_SO)
        val preload = if (hook.exists()) hook.absolutePath else ""
        if (fd < 0) {
            Log.w(
                TAG,
                "No USB file descriptor yet — EDSDK cannot open usbfs until permission + openDevice",
            )
        }
        Log.i(
            TAG,
            "Starting canon-sidecar ${plan.abi} (attempt ${restartCount + 1}) " +
                "usbPermission=$permissionGranted usbFd=$fd path=$path",
        )
        try {
            // Bump epoch before spawn so a failed exec still cancels an in-flight restart wait.
            val epoch = ++spawnEpoch
            attachSpawned(spawnNative(plan, preload, fd, path), fd, epoch)
        } catch (e: Exception) {
            onState("crashed")
            pid = 0
            hasUsbFd = false
            Log.e(TAG, "Failed to exec canon-sidecar: ${e.message}", e)
        }
    }

    private fun spawnNative(
        plan: LaunchPlan,
        preload: String,
        usbFd: Int,
        usbPath: String?,
    ): CanonSidecarSpawner.Spawned =
        CanonSidecarSpawner.spawn(
            CanonSidecarSpawner.SpawnRequest(
                interpreter = plan.interpreter.absolutePath,
                args = spawnArgs(plan, preload),
                cwd = plan.glibcDir.absolutePath,
                usb =
                    CanonSidecarSpawner.UsbInherit(
                        preload = preload,
                        fd = usbFd,
                        path = usbPath,
                    ),
            ),
        )

    private fun spawnArgs(
        plan: LaunchPlan,
        preload: String,
    ): Array<String> =
        buildList {
            add("--library-path")
            add(plan.glibcDir.absolutePath)
            if (preload.isNotEmpty()) {
                add("--preload")
                add(preload)
            }
            add(plan.binary.absolutePath)
        }.toTypedArray()

    private fun attachSpawned(
        spawned: CanonSidecarSpawner.Spawned,
        usbFd: Int,
        epoch: Int,
    ) {
        pid = spawned.pid
        hasUsbFd = usbFd >= 0
        restartCount++
        onState("running")
        adoptStdout(spawned.stdoutFd)
        watchPid(spawned.pid, epoch)
    }

    private fun adoptStdout(stdoutFd: Int) {
        closeStdoutQuietly()
        stdoutPfd = ParcelFileDescriptor.adoptFd(stdoutFd)
        logThread?.interrupt()
        logThread =
            Thread({
                val fd = stdoutPfd?.fileDescriptor ?: return@Thread
                tailLog(FileInputStream(fd))
            }, "canon-log").also { it.start() }
    }

    private fun watchPid(
        childPid: Int,
        epoch: Int,
    ) {
        watchThread =
            Thread({
                val code = CanonSidecarSpawner.waitPid(childPid)
                onChildExited(epoch, code)
            }, "canon-watch").also {
                it.isDaemon = true
                it.start()
            }
    }

    private fun onChildExited(
        epoch: Int,
        code: Int,
    ) {
        if (epoch != spawnEpoch) return
        pid = 0
        hasUsbFd = false
        onState(if (restartCount >= MAX_RESTARTS) "max_restarts" else "crashed")
        Log.w(TAG, "canon-sidecar exited with code $code — restarting in 3 s")
        try {
            Thread.sleep(RESTART_DELAY_MS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return
        }
        if (epoch != spawnEpoch) return
        launch(lastAbi)
    }

    private fun closeStdoutQuietly() {
        try {
            stdoutPfd?.close()
        } catch (e: Exception) {
            Log.w(TAG, "close sidecar stdout: ${e.message}")
        }
        stdoutPfd = null
    }

    private fun tailLog(stream: InputStream) {
        try {
            stream.bufferedReader().forEachLine { line ->
                Log.i(TAG, line)
            }
        } catch (e: Exception) {
            Log.d(TAG, "sidecar log tail ended: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "CanonSidecar"
        private const val MAX_RESTARTS = 10
        private const val RESTART_DELAY_MS = 3_000L
    }
}
