package com.srisarani.fotozenai.canon.eos

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Live view streaming.
 *
 * ## Frame dropping, not queueing
 *
 * The plan is explicit: drop frames rather than queue when decode falls behind. A queued
 * live view drifts further behind real time the longer it runs, which is worse than
 * useless for framing a shot - the user aims at where the subject *was*.
 * [currentFrame] is a `SharedFlow` holding only the newest frame, so a slow consumer
 * naturally misses intermediate frames instead of delaying the stream.
 *
 * ## Bitmap reuse
 *
 * Decoding a fresh bitmap 20 times a second triggers constant GC and makes 15fps
 * unreachable. `inBitmap` reuses one allocation for every frame of the same dimensions.
 */
class EosLiveView(
    private val ptp: PtpSession,
    private val properties: EosProperties,
    private val scope: CoroutineScope,
    private val config: Config = Config(),
) {

    data class Config(
        /**
         * Delay between poll attempts.
         *
         * Measured on hardware 2026-08-13: at 33ms this yielded **12.4 fps**, under the
         * 15 fps acceptance floor. The limit is the `GetViewFinderData` round trip plus
         * the frames where the camera has nothing new to give, not this delay — so the
         * fix is to poll harder and let the empty responses fall through cheaply.
         *
         * 8ms is deliberately below any achievable frame rate. Live view is the only
         * thing using the USB thread while it runs, and a poll returning no frame costs
         * one short transaction.
         */
        val frameIntervalMs: Long = 8,
        /** Consecutive failures before giving up on the stream. */
        val maxConsecutiveFailures: Int = 15,
        /**
         * How long the camera may answer `NotReady` before we call live view broken (`P-21`).
         *
         * The mirror has to flip and the sensor has to start streaming, which is not instant.
         * Generous enough to cover a cold start; short enough that a mode dial in the wrong
         * position produces an error rather than an indefinite black rectangle.
         */
        val warmUpTimeoutMs: Long = 6_000,
    )

    /**
     * The newest frame, as a `SharedFlow` rather than a `StateFlow`.
     *
     * > Fixed on hardware 2026-08-17. This was a `StateFlow<Bitmap?>`, and a `StateFlow`
     * > only emits when the value *changes*. Because [decodeInto] reuses one allocation via
     * > `inBitmap` — the optimisation that makes 20fps reachable — every frame is the **same
     * > Bitmap instance**, so assigning it was a no-op after the first one. The stream ran
     * > perfectly (570 frames, 0 dropped) while the screen showed a frozen first frame.
     *
     * `replay = 1` so a collector attaching mid-stream paints immediately instead of waiting
     * for the next frame, and `DROP_OLDEST` keeps the documented behaviour: a slow consumer
     * misses intermediate frames rather than delaying the stream. For a viewfinder a late
     * frame is worse than a missing one.
     */
    private val _currentFrame = MutableSharedFlow<Bitmap>(
        replay = 1,
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val currentFrame: SharedFlow<Bitmap> = _currentFrame.asSharedFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private var pollJob: Job? = null
    private var reusableBitmap: Bitmap? = null

    var framesReceived: Long = 0
        private set
    var framesDropped: Long = 0
        private set
    private var lastFrameAtMillis = 0L
    private var measuredFps = 0.0

    fun fps(): Double = measuredFps

    /**
     * Routes live view to the host and starts polling.
     *
     * @return false if the camera refused - typically because the mode dial is in a
     *   position that disallows live view, or the photo/movie lever is on movie.
     */
    fun start(): Boolean {
        if (_isRunning.value) return true

        // C-19: TFT+PC keeps the camera's own screen alive. PC-only makes the body show
        // "Busy", which reads as a hung camera to anyone standing at the booth.
        val ok = properties.setUInt32WithRetry(
            EosProperty.EVF_OUTPUT_DEVICE,
            EvfOutputDevice.CAMERA_TFT_AND_PC.toLong(),
        )
        if (!ok) {
            CanonLog.e("Could not route live view to host - check the mode dial and photo/movie lever")
            return false
        }

        framesReceived = 0
        framesDropped = 0
        _isRunning.value = true
        startPolling()
        CanonLog.i("Live view started, target %.0f fps", 1000.0 / config.frameIntervalMs)
        return true
    }

    private fun startPolling() {
        pollJob = scope.launch {
            var consecutiveFailures = 0
            var lastFailure: Exception? = null
            val startedAtMillis = System.currentTimeMillis()
            // C-13: the first frames after enabling are routinely garbage. Discarding a
            // couple avoids a green flash every time live view starts or resumes.
            var framesToDiscard = DISCARD_AFTER_ENABLE

            while (isActive) {
                val tick = pollOnce(framesToDiscard, consecutiveFailures)
                framesToDiscard = tick.framesToDiscard
                consecutiveFailures = tick.consecutiveFailures
                lastFailure = tick.lastFailure ?: lastFailure
                if (shouldStop(startedAtMillis, consecutiveFailures, lastFailure)) {
                    return@launch
                }
                delay(config.frameIntervalMs)
            }
        }
    }

    private fun pollOnce(framesToDiscard: Int, consecutiveFailures: Int): PollTick {
        return try {
            val payload = fetchFrame()
            if (payload != null) {
                acceptFrame(payload, framesToDiscard)
            } else {
                PollTick(framesToDiscard, consecutiveFailures, lastFailure = null)
            }
        } catch (e: PtpException.OperationFailed) {
            // P-21: DeviceBusy *and* Canon's NotReady (0xA102) are both routine here
            // - the camera is mid-something or still spinning live view up. Neither
            // is a failure. Counting NotReady was fatal at this poll rate: 15
            // "failures" elapse in ~120ms, so the stream gave up long before the
            // mirror had even finished flipping.
            if (e.isTransient) {
                PollTick(framesToDiscard, consecutiveFailures, lastFailure = null)
            } else {
                PollTick(framesToDiscard, consecutiveFailures + 1, lastFailure = e)
            }
        } catch (e: Exception) {
            PollTick(framesToDiscard, consecutiveFailures + 1, lastFailure = e)
        }
    }

    private fun acceptFrame(payload: ByteArray, framesToDiscard: Int): PollTick {
        if (framesToDiscard > 0) {
            return PollTick(framesToDiscard - 1, consecutiveFailures = 0, lastFailure = null)
        }
        decodeInto(payload)
        return PollTick(0, consecutiveFailures = 0, lastFailure = null)
    }

    private fun shouldStop(
        startedAtMillis: Long,
        consecutiveFailures: Int,
        lastFailure: Exception?,
    ): Boolean {
        if (framesReceived == 0L &&
            System.currentTimeMillis() - startedAtMillis > config.warmUpTimeoutMs
        ) {
            // P-21: NotReady no longer counts as a failure, so a camera that never wakes
            // would otherwise spin here forever showing a black rectangle.
            CanonLog.e(
                lastFailure,
                "Live view produced no frames within %dms - giving up. " +
                    "Check the mode dial and the photo/movie lever.",
                config.warmUpTimeoutMs,
            )
            _isRunning.value = false
            return true
        }
        if (consecutiveFailures >= config.maxConsecutiveFailures) {
            // C-19: the reason used to be swallowed entirely, so a stream that died
            // after ~55 good frames was indistinguishable from one that never started.
            CanonLog.e(
                lastFailure,
                "Live view stopping after %d consecutive failures (%d good frames first)",
                consecutiveFailures,
                framesReceived,
            )
            _isRunning.value = false
            return true
        }
        return false
    }

    private fun fetchFrame(): ByteArray? {
        val result = ptp.transact(
            CanonEosOperation.GET_VIEWFINDER_DATA,
            VIEWFINDER_REQUEST_FLAG,
            timeoutMs = FRAME_TIMEOUT_MS,
        )
        return result.data
    }

    private fun decodeInto(payload: ByteArray) {
        val jpeg = EvfFrameParser.extractJpeg(payload)
        if (jpeg == null || !EvfFrameParser.looksLikeJpeg(jpeg)) {
            framesDropped++
            return
        }
        val bitmap = decodeJpeg(jpeg) ?: run {
            framesDropped++
            return
        }
        reusableBitmap = bitmap
        framesReceived++
        recordFps()
        // tryEmit, never emit: a suspending emit would stall the poll loop behind a slow
        // consumer, which is the stall this class is built to avoid.
        _currentFrame.tryEmit(bitmap)
    }

    private fun decodeJpeg(jpeg: ByteArray): Bitmap? {
        val options = reuseOptions()
        return try {
            BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, options)
        } catch (_: IllegalArgumentException) {
            // inBitmap could not be reused (size changed). Retry without it.
            reusableBitmap = null
            runCatching {
                BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, freshOptions())
            }.getOrNull()
        }
    }

    private fun reuseOptions(): BitmapFactory.Options =
        freshOptions().apply {
            reusableBitmap?.let { inBitmap = it }
        }

    private fun freshOptions(): BitmapFactory.Options =
        BitmapFactory.Options().apply {
            inScaled = false
            inPreferredConfig = Bitmap.Config.RGB_565 // half the memory; ample for a viewfinder
            inMutable = true
        }

    private fun recordFps() {
        val now = System.currentTimeMillis()
        if (lastFrameAtMillis > 0) {
            val delta = now - lastFrameAtMillis
            if (delta > 0) {
                // Exponential moving average - a per-frame instantaneous figure is too noisy.
                measuredFps = if (measuredFps == 0.0) {
                    1000.0 / delta
                } else {
                    measuredFps * 0.9 + (1000.0 / delta) * 0.1
                }
            }
        }
        lastFrameAtMillis = now
    }

    /**
     * Stops the stream and turns live view off on the camera.
     *
     * Leaving it on holds the mirror up, which drains the battery and heats the sensor
     * (`C-09`). Always called on capture and on teardown.
     */
    fun stop() {
        if (!_isRunning.value && pollJob == null) return

        pollJob?.cancel()
        pollJob = null
        _isRunning.value = false

        properties.trySetUInt32(EosProperty.EVF_OUTPUT_DEVICE, EvfOutputDevice.OFF.toLong())

        // Drop the replayed frame so a collector attaching after a stop does not paint a
        // stale viewfinder from the previous session.
        _currentFrame.resetReplayCache()
        reusableBitmap = null
        lastFrameAtMillis = 0
        measuredFps = 0.0

        CanonLog.i("Live view stopped (%d frames, %d dropped)", framesReceived, framesDropped)
    }

    fun summary(): String =
        "frames=%d dropped=%d fps=%.1f".format(framesReceived, framesDropped, measuredFps)

    private data class PollTick(
        val framesToDiscard: Int,
        val consecutiveFailures: Int,
        val lastFailure: Exception?,
    )

    private companion object {
        /** Request flag used by libgphoto2 for EOS viewfinder data. ⚠️ VERIFY. */
        const val VIEWFINDER_REQUEST_FLAG = 0x00100000L

        /** Short: a stale frame is worthless, so failing fast beats waiting. */
        const val FRAME_TIMEOUT_MS = 1_500

        /** C-13: the first frames after enabling are routinely garbage. */
        const val DISCARD_AFTER_ENABLE = 2
    }
}
