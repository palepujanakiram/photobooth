package com.srisarani.fotozenai.canon.session

import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureQueue
import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.DeviceCapabilityDump
import com.srisarani.fotozenai.canon.ptp.PtpDeviceInfo
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpOperation
import com.srisarani.fotozenai.canon.ptp.PtpSession
import com.srisarani.fotozenai.canon.usb.UsbError
import com.srisarani.fotozenai.canon.usb.UsbTransport
import java.io.File

/**
 * PTP connect helpers used by [CameraSessionManager].
 *
 * Kept out of the manager so handshake retries and capability checks do not push the
 * singleton over Qlty's file-complexity budget.
 */
internal object CameraSessionHandshake {

    /**
     * Read budget for the **first** `GetDeviceInfo` on a freshly claimed interface.
     *
     * Deliberately *short*. This body does not answer its first PTP command after
     * `claimInterface`. Failing fast hands control to the retry, which is the call that works.
     */
    const val FIRST_DEVICE_INFO_TIMEOUT_MS = 1_500
    const val DEVICE_INFO_ATTEMPTS = 3
    const val CAPTURE_DRAIN_TIMEOUT_MS = 15_000L
    const val CAPTURE_DRAIN_POLL_MS = 50L

    fun readDeviceInfoWithRetries(
        ptp: PtpSession,
        transport: UsbTransport,
    ): PtpDeviceInfo {
        var last: Exception? = null
        repeat(DEVICE_INFO_ATTEMPTS) { attempt ->
            try {
                return ptp.getDeviceInfo(timeoutMs = FIRST_DEVICE_INFO_TIMEOUT_MS)
            } catch (e: PtpException) {
                last = e
            } catch (e: UsbError) {
                last = e
            }
            val seen = last
            CanonLog.w(
                "GetDeviceInfo attempt %d/%d failed (%s) - clearing endpoint and retrying",
                attempt + 1,
                DEVICE_INFO_ATTEMPTS,
                seen?.message,
            )
            transport.recoverFromStall()
        }
        throw last ?: PtpException.Malformed("GetDeviceInfo failed with no recorded cause")
    }

    fun writeCapabilityDump(info: PtpDeviceInfo, dir: File?) {
        if (dir == null) return
        runCatching {
            val target = File(dir, DeviceCapabilityDump.suggestedFilename(info))
            target.parentFile?.mkdirs()
            target.writeText(DeviceCapabilityDump.render(info))
            CanonLog.i(
                "Capability dump written to %s - COMMIT THIS to docs/device-capabilities/",
                target.absolutePath,
            )
        }.onFailure { CanonLog.w(it, "Could not write capability dump") }
    }

    fun warnAboutMissingCapabilities(info: PtpDeviceInfo) {
        // Deliberately NOT checking the vendor extension field. A real EOS 200D II reports
        // "Microsoft" there while implementing the full EOS operation set.
        if (!info.isCanonEos) {
            CanonLog.e("Body does not implement the EOS operation set - this is not a tetherable EOS camera")
        }
        if (!info.supportsEosRemoteMode) {
            CanonLog.e("Body does not report the EOS remote-mode opcodes - M3 is blocked on this body")
        }
        if (!info.supportsJpegCapture) {
            CanonLog.e("Body does not report JPEG capture support - plan section 2 assumes it")
        }
        if (!info.supportsOperation(PtpOperation.GET_PARTIAL_OBJECT) &&
            !info.supportsOperation(CanonEosOperation.GET_PARTIAL_OBJECT)
        ) {
            CanonLog.w("No GetPartialObject - M4 must fall back to whole-file GetObject")
        }
    }

    suspend fun awaitCaptureDrained(queue: CaptureQueue?): Boolean {
        if (queue == null) return false
        val completedBefore = queue.capturesCompleted + queue.capturesFailed
        val drained = kotlinx.coroutines.withTimeoutOrNull(CAPTURE_DRAIN_TIMEOUT_MS) {
            while (queue.capturesCompleted + queue.capturesFailed == completedBefore) {
                kotlinx.coroutines.delay(CAPTURE_DRAIN_POLL_MS)
            }
            true
        }
        if (drained == null) {
            CanonLog.w(
                "Image did not reach disk within %dms of the shutter - resuming live view anyway (C-16)",
                CAPTURE_DRAIN_TIMEOUT_MS,
            )
            return false
        }
        return true
    }
}
