package com.srisarani.fotozenai.canon

import android.os.Build
import android.os.Process

/** Maps the device ABI to Canon sidecar JNI / asset layout. */
internal object CanonSidecarAbi {
    const val ARM64 = "arm64-v8a"
    const val ARM32 = "armeabi-v7a"

    const val BINARY_SO = "libcanon_sidecar.so"
    const val BINARY_RUNTIME = "canon-sidecar"
    const val EDSDK_SO = "libEDSDK.so"
    const val USB_HOOK_SO = "libusb_open_hook.so"

    /**
     * ABI of **this process**, not the SoC. 32-bit Android on ARMv8 silicon
     * (armeabi-v7a userspace) must not pick ARM64 just because the kernel can.
     */
    fun resolved(): String? {
        if (Process.is64Bit() && Build.SUPPORTED_64_BIT_ABIS.contains(ARM64)) {
            return ARM64
        }
        if (Build.SUPPORTED_32_BIT_ABIS.contains(ARM32) ||
            Build.SUPPORTED_ABIS.contains(ARM32)
        ) {
            return ARM32
        }
        if (Build.SUPPORTED_ABIS.contains(ARM64)) return ARM64
        return null
    }

    fun interpreterSoName(abi: String): String = when (abi) {
        ARM64 -> "libld_linux_aarch64.so"
        ARM32 -> "libld_linux_armhf.so"
        else -> error("unsupported sidecar abi $abi")
    }

    fun interpreterRuntimeName(abi: String): String = when (abi) {
        ARM64 -> "ld-linux-aarch64.so.1"
        ARM32 -> "ld-linux-armhf.so.3"
        else -> error("unsupported sidecar abi $abi")
    }
}
