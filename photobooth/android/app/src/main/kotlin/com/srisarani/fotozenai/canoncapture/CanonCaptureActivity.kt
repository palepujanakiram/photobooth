package com.srisarani.fotozenai.canoncapture

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.media.MediaActionSound
import android.media.ToneGenerator
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.srisarani.fotozenai.R
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureQueue
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import com.srisarani.fotozenai.canon.state.ConnectionState
import com.srisarani.fotozenai.canon.state.isReadyForCapture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The native DSLR capture screen (`docs/direct-ptp-native-camera-plan.md`, P3).
 *
 * A full-screen Activity rather than a Flutter `PlatformView`: hybrid composition would
 * copy every live-view frame through Flutter's raster thread, which on a 32-bit box with a
 * 256 MB heap is exactly the per-frame cost the POC engineered away with `inBitmap` reuse.
 *
 * P3 is one shot on a button press. The countdown, the Classic multi-shot loop and the
 * idle timeout arrive in P4; [CaptureSessionContract.Request.shotCount] is already honoured
 * so the contract does not have to change again.
 */
class CanonCaptureActivity : Activity() {

    private lateinit var surface: SurfaceView
    private lateinit var statusText: TextView
    private lateinit var titleText: TextView
    private lateinit var countdownText: TextView
    private lateinit var thumbnailStrip: LinearLayout
    private lateinit var shutterButton: Button
    private lateinit var cancelButton: Button

    private var renderer: LiveViewSurfaceRenderer? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var request = CaptureSessionContract.Request()

    private val shots = mutableListOf<CaptureSessionContract.Shot>()
    private var captureJob: Job? = null
    private var idleJob: Job? = null
    private var finished = false

    /**
     * Countdown ticks and the shutter click.
     *
     * Native rather than played from Dart: a channel round trip would land the click after
     * the mirror has already moved, and a shutter sound that arrives late reads as lag.
     */
    private var toneGenerator: ToneGenerator? = null
    private var shutterSound: MediaActionSound? = null

    /**
     * Handles already delivered by the capture queue.
     *
     * `CaptureQueue.completed` is a `SharedFlow` with `replay = 1`, so a fresh collector is
     * immediately handed the previous shot. Without this guard, shot 2 would "complete"
     * instantly with shot 1's file.
     */
    private val consumedHandles = mutableSetOf<Long>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A booth screen must not sleep mid-pose, and the guest is not touching the device.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // One line switches the booth look for the diagnostic one — see CaptureScreenStyle.
        setContentView(CaptureScreenStyle.current.layoutRes)

        request = CaptureSessionContract.Request.fromJson(
            intent.getStringExtra(CaptureSessionContract.EXTRA_REQUEST),
        )

        surface = findViewById(R.id.canon_live_view)
        statusText = findViewById(R.id.canon_status)
        titleText = findViewById(R.id.canon_title)
        countdownText = findViewById(R.id.canon_countdown)
        thumbnailStrip = findViewById(R.id.canon_thumbnails)
        shutterButton = findViewById(R.id.canon_shutter)
        cancelButton = findViewById(R.id.canon_cancel)

        toneGenerator = runCatching {
            ToneGenerator(AudioManager.STREAM_MUSIC, TONE_VOLUME)
        }.getOrNull()
        shutterSound = runCatching { MediaActionSound().apply { load(MediaActionSound.SHUTTER_CLICK) } }
            .getOrNull()

        request.titleText?.let { titleText.text = it }
        // Booth layout only; the diagnostic one has no subtitle line.
        request.subtitleText?.let {
            findViewById<TextView?>(R.id.canon_subtitle)?.text = it
        }
        request.shutterText?.let { shutterButton.text = it }
        request.cancelText?.let { cancelButton.text = it }

        shutterButton.setOnClickListener { onShutter() }
        val cancel = View.OnClickListener {
            finishWith(CaptureSessionContract.Result.cancelled("Cancelled by user"))
        }
        cancelButton.setOnClickListener(cancel)
        // Present only in the booth layout, mirroring the Flutter capture bar's back arrow.
        findViewById<View?>(R.id.canon_back)?.setOnClickListener(cancel)
        // The box reports touch AND d-pad; the shutter must be reachable without a screen tap.
        shutterButton.requestFocus()

        renderer = LiveViewSurfaceRenderer(surface.holder)
        surface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                renderer?.isSurfaceReady = true
            }

            override fun surfaceChanged(holder: SurfaceHolder, f: Int, w: Int, h: Int) = Unit

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                // Must clear before returning, or the render loop draws into a dead surface.
                renderer?.isSurfaceReady = false
            }
        })

        startSession()
    }

    // ------------------------------------------------------------------ session

    private fun startSession() {
        scope.launch {
            setStatus(getString(R.string.canon_status_connecting))

            if (!ensureConnected()) return@launch

            startLiveView()
            startIdleWatchdog()

            if (request.autoStart) {
                runShotSequence()
            } else {
                setStatus(
                    getString(
                        R.string.canon_status_ready_format,
                        shots.size + 1,
                        request.shotCount,
                    ),
                )
                shutterButton.isEnabled = true
            }
        }
    }

    /**
     * Ends the session if it outlives its budget.
     *
     * A guest who walks away mid-strip would otherwise leave the booth sitting on a native
     * screen with no way back — the Flutter side is blocked awaiting this Activity, so
     * nothing else can recover it.
     */
    private fun startIdleWatchdog() {
        idleJob = scope.launch {
            delay(request.idleTimeoutSeconds * 1000L)
            CanonLog.w("Capture session idle for %ds — abandoning", request.idleTimeoutSeconds)
            finishWith(
                CaptureSessionContract.Result.cancelled(
                    "No photos completed within ${request.idleTimeoutSeconds}s",
                ),
            )
        }
    }

    /** Countdown → shot → rearrange, repeated [CaptureSessionContract.Request.shotCount] times. */
    private suspend fun runShotSequence() {
        shutterButton.isEnabled = false
        while (shots.size < request.shotCount && !finished) {
            val shotNumber = shots.size + 1

            // Between shots, hold on the viewfinder so guests can rearrange. Skipped before
            // the first shot: the countdown is the guest's cue to get into position.
            if (shotNumber > 1 && request.betweenShotSeconds > 0) {
                holdForRearrange(shotNumber)
            }

            runCountdown(shotNumber)
            if (finished) return

            val ok = runOneShot()
            if (!ok) {
                // A failed shot is retried rather than abandoning the strip — the guest is
                // still standing there, and losing three good shots to one bad one is worse
                // than an extra countdown.
                setStatus(getString(R.string.canon_status_capture_failed))
                delay(RETRY_PAUSE_MS)
            }
        }
    }

    private suspend fun holdForRearrange(nextShot: Int) {
        for (remaining in request.betweenShotSeconds downTo 1) {
            if (finished) return
            setStatus(
                getString(
                    R.string.canon_status_rearrange_format,
                    nextShot,
                    request.shotCount,
                    remaining,
                ),
            )
            delay(1000)
        }
    }

    private suspend fun runCountdown(shotNumber: Int) {
        for (remaining in request.countdownSeconds downTo 1) {
            if (finished) return
            countdownText.visibility = View.VISIBLE
            countdownText.text = remaining.toString()
            setStatus(
                getString(R.string.canon_status_pose_format, shotNumber, request.shotCount),
            )
            if (remaining <= COUNTDOWN_BEEP_FROM) beep()
            delay(1000)
        }
        countdownText.visibility = View.GONE
    }

    /** Connects if needed; finishes the Activity with a typed error if it cannot. */
    private suspend fun ensureConnected(): Boolean {
        if (CameraSessionManager.state.value.isReadyForCapture) return true

        clearStalePtpSessionIfNeeded()

        repeat(2) { attempt ->
            CameraSessionManager.scanAndConnect(applicationContext)
            val settled = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
                CameraSessionManager.state.first {
                    it.isConnectOutcome() || it.isReadyForCapture
                }
            }

            when (val state = settled ?: CameraSessionManager.state.value) {
                is ConnectionState.Ready,
                is ConnectionState.RemoteMode,
                is ConnectionState.LiveView,
                -> return true

                is ConnectionState.PermissionDenied -> finishWith(
                    CaptureSessionContract.Result.error(
                        CaptureSessionContract.ERROR_PERMISSION_DENIED,
                        "USB permission was refused for the camera",
                    ),
                )

                is ConnectionState.NoDevice -> finishWith(
                    CaptureSessionContract.Result.error(
                        CaptureSessionContract.ERROR_NO_DEVICE,
                        "No camera found. Check the cable and that the camera is switched on.",
                    ),
                )

                is ConnectionState.NoUsbHostSupport -> finishWith(
                    CaptureSessionContract.Result.error(
                        CaptureSessionContract.ERROR_CONNECT_FAILED,
                        "This device cannot host USB",
                    ),
                )

                else -> if (attempt == 0) {
                    CanonLog.w(
                        "Connect attempt ${attempt + 1} stalled at $state — retrying",
                    )
                    CameraSessionManager.disconnectAndAwait()
                    delay(RETRY_PAUSE_MS)
                } else {
                    finishWith(
                        CaptureSessionContract.Result.error(
                            CaptureSessionContract.ERROR_CONNECT_FAILED,
                            describe(state),
                        ),
                    )
                }
            }
            if (finished) return false
        }
        return false
    }

    /** Drops a half-open USB/PTP session so the next scan can start clean. */
    private suspend fun clearStalePtpSessionIfNeeded() {
        when (CameraSessionManager.state.value) {
            is ConnectionState.Error,
            is ConnectionState.Wedged,
            is ConnectionState.SessionOpen,
            is ConnectionState.Opened,
            -> CameraSessionManager.disconnectAndAwait()

            else -> Unit
        }
    }

    private fun startLiveView() {
        val liveView = CameraSessionManager.liveView
        if (liveView == null) {
            CanonLog.w("No live view available; capture will run without a viewfinder")
            return
        }
        if (!liveView.isRunning.value) {
            CameraSessionManager.toggleLiveView()
        }

        // Frames are decoded on the USB thread and drawn here. The StateFlow holds only the
        // newest frame, so falling behind drops frames instead of accumulating lag — which
        // for a viewfinder is the correct trade: a late frame is worse than a missing one.
        scope.launch {
            liveView.currentFrame.collect { frame: Bitmap ->
                withContext(Dispatchers.Default) { renderer?.draw(frame) }
            }
        }
    }

    // ------------------------------------------------------------------ capture

    private fun onShutter() {
        if (captureJob?.isActive == true) return
        shutterButton.isEnabled = false
        captureJob = scope.launch { runOneShot() }
    }

    /** Fires one shot and stores it. Returns false when the shot did not land. */
    private suspend fun runOneShot(): Boolean {
        val queue = CameraSessionManager.captureQueue
        if (queue == null) {
            finishWith(
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_CAPTURE_FAILED,
                    "Capture queue unavailable — the camera session is not fully open",
                ),
            )
            return false
        }

        setStatus(getString(R.string.canon_status_capturing))
        shutterSound()

        // Subscribe BEFORE firing, and UNDISPATCHED so the collector is attached before
        // this line returns. A download can finish faster than a coroutine scheduled the
        // ordinary way would take to start collecting, and the event would be missed.
        val done = scope.async(start = CoroutineStart.UNDISPATCHED) {
            queue.completed.first { it.handle !in consumedHandles }
        }

        CameraSessionManager.triggerCapture(withAutofocus = true)

        val completed = withTimeoutOrNull(CAPTURE_TIMEOUT_MS) { done.await() }
        done.cancel()

        if (completed == null) {
            setStatus(getString(R.string.canon_status_capture_failed))
            shutterButton.isEnabled = !request.autoStart
            CanonLog.e("Capture timed out after %dms", CAPTURE_TIMEOUT_MS)
            return false
        }

        consumedHandles += completed.handle
        onCaptured(completed)
        return true
    }

    private suspend fun onCaptured(done: CaptureQueue.Item.Done) {
        setStatus(getString(R.string.canon_status_processing))

        val original = done.image.file
        // Decode off the main thread: even subsampled, this is tens of milliseconds and
        // would otherwise stutter the viewfinder.
        val derivative = withContext(Dispatchers.Default) {
            DisplayDerivative.create(
                original = original,
                maxLongEdge = request.displayMaxLongEdge,
                jpegQuality = request.displayJpegQuality,
            )
        }

        shots += CaptureSessionContract.Shot(
            originalPath = original.absolutePath,
            displayPath = derivative?.file?.absolutePath,
            widthPx = derivative?.originalWidthPx ?: 0,
            heightPx = derivative?.originalHeightPx ?: 0,
            bytes = done.image.sizeBytes,
            capturedAtMs = System.currentTimeMillis(),
        )

        CanonLog.i(
            "Shot %d/%d stored: %s (%d bytes, %dms)",
            shots.size,
            request.shotCount,
            original.name,
            done.image.sizeBytes,
            done.elapsedMs,
        )

        addThumbnail(derivative?.file?.absolutePath)

        if (shots.size >= request.shotCount) {
            finishWith(
                CaptureSessionContract.Result(
                    status = CaptureSessionContract.STATUS_COMPLETED,
                    shots = shots.toList(),
                ),
            )
        } else if (!request.autoStart) {
            setStatus(
                getString(R.string.canon_status_ready_format, shots.size + 1, request.shotCount),
            )
            shutterButton.isEnabled = true
        }
    }

    /**
     * Adds the shot to the strip so guests can see the set building.
     *
     * Decoded small and off the main thread — these come from the display derivative, not
     * the original, and a thumbnail is never a reason to touch a 6000×4000 file.
     */
    private suspend fun addThumbnail(displayPath: String?) {
        if (displayPath == null || request.shotCount <= 1) return
        val bitmap = withContext(Dispatchers.Default) {
            runCatching {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(displayPath, bounds)
                val options = BitmapFactory.Options().apply {
                    inSampleSize = DisplayDerivative
                        .sampleSizeFor(bounds.outWidth, bounds.outHeight, THUMBNAIL_LONG_EDGE)
                }
                BitmapFactory.decodeFile(displayPath, options)
            }.getOrNull()
        } ?: return

        val view = ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                THUMBNAIL_WIDTH_PX,
                LinearLayout.LayoutParams.MATCH_PARENT,
            ).also { it.marginEnd = THUMBNAIL_GAP_PX }
            scaleType = ImageView.ScaleType.CENTER_CROP
            setImageBitmap(bitmap)
        }
        thumbnailStrip.addView(view)
        thumbnailStrip.visibility = View.VISIBLE
    }

    // ------------------------------------------------------------------ lifecycle

    private fun finishWith(result: CaptureSessionContract.Result) {
        if (finished) return
        finished = true
        CanonLog.i("Capture session %s with %d shot(s)", result.status, result.shots.size)
        stopLiveView()
        setResult(RESULT_OK, result.toIntent())
        finish()
        // Match the Flutter route transition: this should read as a screen change inside
        // one app, not as switching to a different app.
        overridePendingTransition(0, 0)
    }

    private fun stopLiveView() {
        runCatching {
            if (CameraSessionManager.liveView?.isRunning?.value == true) {
                CameraSessionManager.toggleLiveView()
            }
        }
        renderer?.clear()
    }

    override fun onBackPressed() {
        finishWith(CaptureSessionContract.Result.cancelled("Back pressed"))
    }

    override fun onDestroy() {
        // Leave the camera connected: the session is process-scoped and reconnecting for
        // every shot would cost seconds and an extra permission round trip.
        stopLiveView()
        renderer = null
        idleJob?.cancel()
        runCatching { toneGenerator?.release() }
        runCatching { shutterSound?.release() }
        toneGenerator = null
        shutterSound = null
        scope.cancel()
        super.onDestroy()
    }

    /** Sound is a nicety; a device with no audio focus must not break the capture. */
    private fun beep() {
        runCatching { toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_MS) }
    }

    private fun shutterSound() {
        runCatching { shutterSound?.play(MediaActionSound.SHUTTER_CLICK) }
    }

    private fun setStatus(text: String) {
        statusText.text = text
        statusText.visibility = View.VISIBLE
    }

    private fun describe(state: ConnectionState?): String = when (state) {
        is ConnectionState.Error -> state.message
        is ConnectionState.Wedged -> state.reason
        null -> "Timed out waiting for the camera"
        else -> state::class.simpleName ?: "Unknown camera state"
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 30_000L

        /** Beep only on the closing seconds — a beep every second for 10s is irritating. */
        const val COUNTDOWN_BEEP_FROM = 3
        const val BEEP_MS = 150
        const val TONE_VOLUME = 80

        /** Pause after a failed shot before retrying, so the body can settle. */
        const val RETRY_PAUSE_MS = 1_500L

        const val THUMBNAIL_LONG_EDGE = 320
        const val THUMBNAIL_WIDTH_PX = 150
        const val THUMBNAIL_GAP_PX = 12

        /**
         * Shutter to image-on-disk.
         *
         * Wide because the body can answer `DeviceBusy` for ~8s after a release while the
         * image is still in its buffer (`P-18`), and the download itself follows.
         */
        const val CAPTURE_TIMEOUT_MS = 45_000L
    }
}

private fun ConnectionState.isConnectOutcome(): Boolean = when (this) {
    is ConnectionState.Ready,
    is ConnectionState.Error,
    is ConnectionState.PermissionDenied,
    is ConnectionState.NoDevice,
    is ConnectionState.NoUsbHostSupport,
    is ConnectionState.Detached,
    is ConnectionState.Wedged,
    -> true

    else -> false
}
