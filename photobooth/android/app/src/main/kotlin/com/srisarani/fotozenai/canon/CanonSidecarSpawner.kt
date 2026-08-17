package com.srisarani.fotozenai.canon

/**
 * Fork+exec the glibc Canon sidecar so a UsbManager file descriptor survives
 * exec. Android's [ProcessBuilder] closes every fd except stdin/stdout/stderr,
 * which makes EDSDK's libusb hit EACCES on usbfs device nodes.
 */
internal object CanonSidecarSpawner {
    init {
        System.loadLibrary("canon_sidecar_spawn")
    }

    data class Spawned(
        val pid: Int,
        val stdoutFd: Int,
    )

    data class UsbInherit(
        val preload: String,
        val fd: Int,
        val path: String?,
    )

    data class SpawnRequest(
        val interpreter: String,
        val args: Array<String>,
        val cwd: String,
        val usb: UsbInherit,
    )

    fun spawn(request: SpawnRequest): Spawned {
        val result =
            nativeSpawn(
                request.interpreter,
                request.args,
                request.cwd,
                request.usb.preload,
                request.usb.fd,
                request.usb.path,
            ) ?: error("nativeSpawn returned null")
        if (result.size < 2 || result[0] <= 0) {
            error("nativeSpawn failed")
        }
        return Spawned(pid = result[0], stdoutFd = result[1])
    }

    fun waitPid(pid: Int): Int = nativeWaitPid(pid)

    fun kill(pid: Int) {
        if (pid > 0) {
            nativeKill(pid)
        }
    }

    @JvmStatic
    private external fun nativeSpawn(
        interpreter: String,
        args: Array<String>,
        cwd: String,
        preload: String,
        usbFd: Int,
        usbPath: String?,
    ): IntArray?

    @JvmStatic
    private external fun nativeWaitPid(pid: Int): Int

    @JvmStatic
    private external fun nativeKill(pid: Int)
}
