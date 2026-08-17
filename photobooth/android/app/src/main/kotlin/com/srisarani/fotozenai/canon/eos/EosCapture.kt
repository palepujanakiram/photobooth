package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpObjectInfo
import com.srisarani.fotozenai.canon.ptp.PtpOperation
import com.srisarani.fotozenai.canon.ptp.PtpSession
import kotlinx.coroutines.delay
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Capture and download for Canon EOS bodies.
 *
 * ## The three things that make capture work
 *
 * 1. **The capacity hack (`P-05`).** With capture destination set to the host, EOS bodies
 *    also want a fake free-space value or they behave as though the host is full. Capture
 *    then fails in a way that looks like a release problem.
 * 2. **The release sequence.** `RemoteReleaseOn(1)` is a shutter half-press (autofocus);
 *    `RemoteReleaseOn(2)` is the full press. They must be released in reverse order.
 *    Skipping the half-press means no AF.
 * 3. **`TransferComplete` after every download.** Omitting it leaves the camera in a
 *    stuck state, and the *second* capture fails while the first looked perfect. This is
 *    the single most common "works once" bug in EOS tethering.
 *
 * And the thing that makes capture *appear* not to work: the event loop not draining
 * (`C-01`). Nothing in this class can compensate for that.
 */
class EosCapture(
    private val ptp: PtpSession,
    private val properties: EosProperties,
    private val config: Config = Config(),
) {

    data class Config(
        /**
         * Fake free space reported to the camera, in bytes.
         *
         * libgphoto2 uses 0x1000000 (16MB). The value does not need to be honest - it
         * just has to be non-zero, or the camera treats the host as full (`P-05`).
         */
        val fakeCapacityBytes: Long = 0x1000000,

        /** Chunk size for `GetPartialObject`. Plan M4: benchmark 1–4MB. */
        val downloadChunkBytes: Int = 2 * 1024 * 1024,

        /** How long to wait for AF before giving up (`C-02`). */
        val autofocusTimeoutMs: Long = 3_000,

        /** Read timeout for a download chunk. Generous: this is the slow path. */
        val downloadTimeoutMs: Int = 30_000,
    )

    /**
     * Puts the camera into host-capture mode.
     *
     * ## Order matters, and it is the opposite of what seems intuitive
     *
     * **Destination first, capacity second.** Verified on hardware 2026-08-13: with the
     * order reversed the destination write is accepted without error and then silently
     * ignored — the camera writes the image to its card and emits `StorageInfoChanged`
     * instead of `ObjectAdded`, so the host waits forever for a photo that was never
     * offered to it. Nothing errors. This matches libgphoto2, where the capacity call
     * carries the comment *"have to do this to get the camera to actually save to the
     * host"* and comes **after** the destination is set.
     */
    fun configureForHostCapture() {
        CanonLog.i("Configuring host capture (P-05)")

        // ---- 1. Destination.
        //
        // BOTH, not HOST: the card keeps the original as an archive while the host still
        // receives every frame over USB. HOST-only means exactly one copy of a photo that
        // cannot be reshot, living on a device whose app-scoped storage is deleted with the
        // app. The card costs nothing and survives a reflash.
        //
        // Note card-only would not work at all — with CAMERA_CARD the image never crosses
        // USB, so there is nothing to make a print derivative from.
        val destinationOk = properties.setUInt32WithRetry(
            EosProperty.CAPTURE_DESTINATION,
            EosCaptureDestination.BOTH.toLong(),
        )
        if (!destinationOk) {
            CanonLog.e("Capture destination not set - images may go to the card only")
        }

        // ---- 2. The capacity hack (P-05).
        //
        // This is an OPERATION (EOS_PCHDDCapacity, 0x911A), not a device property.
        // Confirmed present on the 200D II via the M2 capability dump. Writing property
        // 0xD11A instead returns DeviceBusy on every attempt - which reads as transient
        // and invites a retry loop that can never succeed.
        //
        // Parameters follow libgphoto2: (capacityInBlocks, blockSize, flag).
        val capacityOk = runCatching {
            ptp.transact(
                CanonEosOperation.PC_HDD_CAPACITY,
                CAPACITY_BLOCKS,
                CAPACITY_BLOCK_SIZE,
                CAPACITY_FLAG,
            )
        }.onFailure {
            CanonLog.e(it, "EOS_PCHDDCapacity failed (P-05) - host capture will fail as 'disk full'")
        }.isSuccess

        // Report the destination actually written. The POC logged a hardcoded
        // "destination=host" here, which contradicts the BOTH the line above sets — and a
        // log that disagrees with the code is worse than no log, because it is the first
        // thing anyone checks when photos turn out to be missing from the card.
        if (capacityOk) {
            CanonLog.i(
                "Host capture configured: destination=%s (card+host), capacity announced",
                if (destinationOk) "both" else "UNSET",
            )
        }
    }

    /**
     * Forces the body out of self-timer so the shutter fires immediately.
     *
     * The countdown a booth guest sees is the camera's own drive mode, not anything the app
     * adds — see [EosDriveMode]. Best-effort: with the mode dial in an Auto position this
     * property is read-only (`C-04`), and a booth that cannot change it is still better off
     * running than refusing to start.
     *
     * @return the mode actually in force, or null if it could not be set.
     */
    fun useSingleShotDrive(): Long? {
        val ok = properties.setUInt32WithRetry(EosProperty.DRIVE_MODE, EosDriveMode.SINGLE_SHOT)
        if (!ok) {
            CanonLog.w(
                "Could not clear the camera's self-timer - the shutter will still count down. " +
                    "Set drive mode to single-shot on the body (mode dial may need to leave Auto).",
            )
            return null
        }
        CanonLog.i("Drive mode set to %s", EosDriveMode.name(EosDriveMode.SINGLE_SHOT))
        return EosDriveMode.SINGLE_SHOT
    }

    /** Restores card capture. Used on teardown so the camera is left usable standalone. */
    fun restoreCardCapture() {
        properties.trySetUInt32(
            EosProperty.CAPTURE_DESTINATION,
            EosCaptureDestination.CAMERA_CARD.toLong(),
        )
    }

    // ------------------------------------------------------------------ release

    enum class ReleaseMode {
        /** Half-press for AF, then full press. The normal path. */
        WITH_AUTOFOCUS,

        /**
         * Full press only, no AF.
         *
         * The fallback when AF cannot lock (`C-02`) - in low light, on low-contrast
         * subjects, or with the lens in MF. Better a possibly-soft frame than a hang.
         */
        WITHOUT_AUTOFOCUS,
    }

    /**
     * Fires the shutter.
     *
     * Does **not** wait for the image: the object arrives asynchronously as an
     * [EosEvent.ObjectAdded] on the event loop, which is what the capture queue consumes.
     * Deliberately so - blocking here would serialise shutter and transfer and roughly
     * halve the achievable shot rate.
     */
    suspend fun release(mode: ReleaseMode = ReleaseMode.WITH_AUTOFOCUS) {
        CanonLog.i("Shutter release (%s)", mode)

        try {
            if (mode == ReleaseMode.WITH_AUTOFOCUS) {
                // Half press: triggers AF. AF outcome arrives as an event; see C-02.
                busyRetry { ptp.transact(CanonEosOperation.REMOTE_RELEASE_ON, HALF_PRESS, 0) }
            }

            // Full press: fires the shutter.
            busyRetry { ptp.transact(CanonEosOperation.REMOTE_RELEASE_ON, FULL_PRESS, 0) }

            // Release in reverse order. Leaving the button virtually held down blocks the
            // next capture.
            busyRetry { ptp.transact(CanonEosOperation.REMOTE_RELEASE_OFF, FULL_PRESS) }
            if (mode == ReleaseMode.WITH_AUTOFOCUS) {
                busyRetry { ptp.transact(CanonEosOperation.REMOTE_RELEASE_OFF, HALF_PRESS) }
            }
        } catch (e: PtpException.OperationFailed) {
            if (e.isUnsupported) {
                CanonLog.w("RemoteReleaseOn/Off unsupported, falling back to RemoteRelease")
                ptp.transact(CanonEosOperation.REMOTE_RELEASE)
                return
            }
            throw e
        }
    }

    /**
     * Retries an operation while the camera answers `DeviceBusy` (`P-07`).
     *
     * ## Why the shutter needs this
     *
     * Observed on hardware 2026-08-13: firing again shortly after a capture returns
     * `DeviceBusy` on `RemoteReleaseOn` — the body is still processing the previous frame.
     * Two of four rapid presses were simply lost. From the user's side that is a shutter
     * button that sometimes does nothing, with no feedback, which is far worse than a
     * short wait.
     *
     * `DeviceBusy` is the one response code that is explicitly transient and worth
     * retrying blind. Anything else is a real answer and propagates immediately.
     *
     * ## Why this suspends rather than sleeps (`C-16`)
     *
     * **`Thread.sleep` here deadlocks the capture pipeline.** All USB I/O shares one
     * thread (`CameraSessionManager.usbDispatcher`) — including [CaptureQueue]'s download
     * coroutine. The camera reports `DeviceBusy` precisely *because* an image is pending
     * download, so blocking the thread freezes the one coroutine that could drain the
     * buffer and clear the condition being waited on. The retry then guarantees the
     * failure it is retrying against, and every subsequent action reports busy forever.
     *
     * `delay` yields the thread, so the download runs during the wait and the busy state
     * actually clears.
     */
    private suspend fun <T> busyRetry(
        maxAttempts: Int = BUSY_MAX_ATTEMPTS,
        initialDelayMs: Long = 120,
        block: () -> T,
    ): T {
        var delayMs = initialDelayMs
        var lastError: PtpException.OperationFailed? = null

        repeat(maxAttempts) { attempt ->
            try {
                return block()
            } catch (e: PtpException.OperationFailed) {
                if (!e.isBusy) throw e
                lastError = e
                if (attempt < maxAttempts - 1) {
                    CanonLog.d("Camera busy, retrying in %dms (attempt %d/%d)", delayMs, attempt + 1, maxAttempts)
                    delay(delayMs)
                    // Capped growth: the wait we are riding out is bounded (the camera
                    // clears once its pending image is drained), so unbounded doubling
                    // would just oversleep past the moment it became ready.
                    delayMs = ((delayMs * 3) / 2).coerceAtMost(BUSY_MAX_DELAY_MS)
                }
            }
        }
        CanonLog.e(
            "Camera still busy after %d attempts (~%ds). A previous image is probably still " +
                "pending download - the camera stays busy until its buffer is drained.",
            maxAttempts,
            BUSY_TOTAL_BUDGET_SECONDS,
        )
        throw lastError ?: IllegalStateException("busyRetry exhausted without an error")
    }

    /**
     * Looks up an object's camera filename via `GetObjectInfo`.
     *
     * Needed because `ObjectAddedEx64` — the event this body actually sends — carries no
     * filename. Best-effort: returns a synthesized name on failure, because losing a
     * downloaded image over a cosmetic label would be absurd.
     */
    fun resolveFilename(objectHandle: Long): String =
        runCatching {
            val result = ptp.transact(PtpOperation.GET_OBJECT_INFO, objectHandle)
            result.data
                ?.let { PtpObjectInfo.parse(it).filename }
                ?.takeIf { it.isNotBlank() }
                ?: fallbackName(objectHandle)
        }.getOrElse {
            CanonLog.d("GetObjectInfo failed for 0x%08X, using a synthesized name", objectHandle)
            fallbackName(objectHandle)
        }

    private fun fallbackName(handle: Long) = "IMG_%08X.JPG".format(handle)

    /** Triggers autofocus without firing. Used by tap-to-focus in M7. */
    fun autofocus(): Boolean =
        runCatching { ptp.transact(CanonEosOperation.DO_AF, 1) }
            .onFailure { CanonLog.w("DoAf failed: %s", it.message) }
            .isSuccess

    fun cancelAutofocus() {
        runCatching { ptp.transact(CanonEosOperation.AF_CANCEL) }
    }

    // ----------------------------------------------------------------- download

    /** Progress callback: bytes so far, total expected. */
    fun interface ProgressListener {
        fun onProgress(bytesRead: Long, bytesTotal: Long)
    }

    class DownloadResult(
        val bytes: ByteArray,
        val objectHandle: Long,
        val elapsedMs: Long,
    ) {
        val throughputMbPerSec: Double
            get() = if (elapsedMs > 0) (bytes.size / 1_048_576.0) / (elapsedMs / 1000.0) else 0.0
    }

    /**
     * Downloads an object in chunks and signals `TransferComplete`.
     *
     * @param expectedSize the size from the object-added event. **Verified against the
     *   bytes actually received** — a short read that returned without error is `P-08`,
     *   the most dangerous failure here because nothing errors and the file is simply
     *   truncated. Cheap to check, catastrophic to miss.
     */
    fun download(
        objectHandle: Long,
        expectedSize: Long,
        progress: ProgressListener? = null,
    ): DownloadResult {
        val started = System.nanoTime()
        val buffer = ByteArray(expectedSize.toInt())
        var offset = 0L

        CanonLog.i(
            "Download start: handle=0x%08X size=%,d bytes chunk=%,d",
            objectHandle,
            expectedSize,
            config.downloadChunkBytes,
        )

        while (offset < expectedSize) {
            val remaining = expectedSize - offset
            val chunkSize = minOf(config.downloadChunkBytes.toLong(), remaining).toInt()

            val result = ptp.transact(
                partialObjectOpcode(),
                objectHandle,
                offset,
                chunkSize.toLong(),
                timeoutMs = config.downloadTimeoutMs,
            )

            val chunk = result.data
                ?: throw PtpException.Malformed(
                    "GetPartialObject returned no data at offset $offset of $expectedSize",
                )

            if (chunk.isEmpty()) {
                throw PtpException.Malformed(
                    "GetPartialObject returned an empty chunk at offset $offset - " +
                        "download cannot progress",
                )
            }

            chunk.copyInto(buffer, offset.toInt())
            offset += chunk.size
            progress?.onProgress(offset, expectedSize)
        }

        // ---- P-08: verify. A truncated file that returned cleanly is the silent killer.
        if (offset != expectedSize) {
            throw PtpException.Malformed(
                "Downloaded $offset bytes but the camera declared $expectedSize (P-08 truncation)",
            )
        }

        // ---- The one that makes the SECOND capture work.
        signalTransferComplete(objectHandle)

        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        val result = DownloadResult(buffer, objectHandle, elapsedMs)
        CanonLog.i(
            "Download done: %,d bytes in %dms (%.1f MB/s)",
            buffer.size,
            elapsedMs,
            result.throughputMbPerSec,
        )
        return result
    }

    /**
     * Tells the camera the host is finished with the object.
     *
     * **Omitting this is the classic "first capture works, second one hangs" bug.** Failure
     * is logged rather than thrown: we already have the bytes, and turning a successful
     * download into an exception would be worse than the risk of a stuck next capture.
     */
    private fun signalTransferComplete(objectHandle: Long) {
        runCatching { ptp.transact(CanonEosOperation.TRANSFER_COMPLETE, objectHandle) }
            .onFailure {
                CanonLog.e(
                    it,
                    "TransferComplete failed for handle 0x%08X - the NEXT capture may hang",
                    objectHandle,
                )
            }
    }

    /**
     * Cancels an in-flight transfer.
     *
     * Note `EOS_ResetTransfer` (0x9119) is **not present on the 200D II** (`P-13`), so
     * `CancelTransfer` (0x9118, confirmed present) is the only recovery available here.
     */
    fun cancelTransfer() {
        runCatching { ptp.transact(CanonEosOperation.CANCEL_TRANSFER) }
            .onFailure { CanonLog.w(it, "CancelTransfer failed") }
    }

    /**
     * Prefers the EOS partial-object opcode, falling back to the standard one.
     *
     * Both are present on the 200D II. The EOS variant is what libgphoto2 uses for EOS
     * bodies and is the safer default.
     */
    private fun partialObjectOpcode(): Int {
        val info = ptp.cachedDeviceInfo ?: return CanonEosOperation.GET_PARTIAL_OBJECT
        return when {
            info.supportsOperation(CanonEosOperation.GET_PARTIAL_OBJECT) ->
                CanonEosOperation.GET_PARTIAL_OBJECT
            info.supportsOperation(PtpOperation.GET_PARTIAL_OBJECT) ->
                PtpOperation.GET_PARTIAL_OBJECT
            else -> CanonEosOperation.GET_PARTIAL_OBJECT
        }
    }

    private companion object {
        /** Shutter half-press: triggers autofocus. */
        const val HALF_PRESS = 1L

        /** Shutter full press: fires. */
        const val FULL_PRESS = 2L

        // EOS_PCHDDCapacity parameters, following libgphoto2. The numbers are a declared
        // free-space fiction; they only have to be non-zero and plausible.
        const val CAPACITY_BLOCKS = 0x100000L
        const val CAPACITY_BLOCK_SIZE = 0x1000L
        const val CAPACITY_FLAG = 0x1L

        /**
         * Busy-retry budget, sized from hardware observation (2026-08-13).
         *
         * A 200D II stayed `DeviceBusy` for up to ~8 seconds after a capture while an
         * image was still pending download. An initial 1.6s budget dropped roughly half of
         * a rapid-fire sequence. 12 attempts with growth capped at 1s gives ~10s, which
         * covered every case observed.
         */
        const val BUSY_MAX_ATTEMPTS = 12
        const val BUSY_MAX_DELAY_MS = 1_000L
        const val BUSY_TOTAL_BUDGET_SECONDS = 10
    }
}
