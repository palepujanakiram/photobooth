package com.srisarani.fotozenai.canoncapture

import android.app.Activity
import android.graphics.Bitmap
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
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
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

    /** USB downloads finished; derivative work may still be in flight. */
    private var capturesCompleted = 0

    private val derivativeJobs = mutableListOf<Deferred<Unit>>()

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
        bindTopBarActions()
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

    /**
     * Wires the top-bar actions that mirror the Flutter capture AppBar.
     *
     * All three are looked up as nullable: the diagnostic layout deliberately has no chrome,
     * and a hard `findViewById` would crash it rather than simply showing nothing.
     *
     * Only *reconnect* has real work to do. On the Flutter screen "select camera" and
     * "rotate" drive CameraX — choosing between a front/back/UVC device, and re-orienting a
     * preview whose sensor rotation the plugin reports. Neither exists here: there is one
     * tethered body, and its live-view frames arrive already upright. They are kept so the
     * two screens look identical, and disabled so they cannot promise something that will
     * not happen. See [LiveViewSurfaceRenderer] if rotation ever becomes real.
     */
    private fun bindTopBarActions() {
        findViewById<View?>(R.id.canon_reconnect)?.setOnClickListener {
            if (captureJob?.isActive == true) return@setOnClickListener
            setStatus(getString(R.string.canon_status_reconnecting))
            CanonLog.i("Operator asked for a reconnect from the capture screen")
            CameraSessionManager.scanAndConnect(applicationContext)
        }
        findViewById<View?>(R.id.canon_select_camera)?.apply {
            isEnabled = false
            alpha = DISABLED_ACTION_ALPHA
        }
        findViewById<View?>(R.id.canon_rotate)?.apply {
            isEnabled = false
            alpha = DISABLED_ACTION_ALPHA
        }
    }

    // ------------------------------------------------------------------ session

    private fun startSession() {
        scope.launch {
            setStatus(getString(R.string.canon_status_connecting))

            if (!ensureConnected()) return@launch

            seedStaleCaptureReplay()

            startLiveView()
            startIdleWatchdog()

            if (request.autoStart) {
                startShotSequence()
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
        // Restartable, and restarted after every landed shot. It used to be a single timer
        // from session start, which measured how long the *strip* took rather than how long
        // the guest had been idle. A 4-shot strip that hits a couple of DeviceBusy releases
        // takes well over 180s, so the watchdog cancelled a session that was progressing
        // perfectly well — the native screen returned `cancelled`, Dart took that as "leave
        // POSE", and three good photos were thrown away with the guest dumped back on the
        // Terms screen. Observed on hardware 2026-08-18.
        idleJob?.cancel()
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
        while (capturesCompleted < request.shotCount && !finished) {
            val shotNumber = capturesCompleted + 1

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
            // drop(1) discards the value the StateFlow replays on subscription — the state as
            // it was *before* the scan above could change it. Without it this whole wait
            // collapsed: the manager sits at ConnectionState.NoDevice, isConnectOutcome()
            // counts NoDevice as terminal, so `first` matched that stale value immediately and
            // POSE reported "No camera found" roughly 90ms in — while the very same connect
            // went on to succeed seconds later. Observed on hardware 2026-08-18.
            // CanonPtpMethodChannel's connect already does this; only this copy was missing it.
            val settled = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
                CameraSessionManager.state.drop(1).first {
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

    /**
     * "Take shot" starts the countdown, it does not fire the shutter.
     *
     * It used to call [runOneShot] directly, so the press *was* the shot — no countdown, no
     * time to pose. The countdown only ever ran on the auto-start path. Now the press is the
     * cue and [runShotSequence] owns the rest: countdown, shot, rearrange hold, repeat. One
     * press therefore runs a whole Classic strip, which is what the guest wants — walking
     * back to the screen between shots of a 4-shot strip is not a booth experience.
     */
    private fun onShutter() = startShotSequence()

    /**
     * The one and only way a strip starts, whether by auto-start or by the button.
     *
     * Both paths must go through here, and [captureJob] must always be the job doing the
     * work. Auto-start used to call [runShotSequence] inline, leaving `captureJob` null for
     * the whole strip — so the "hand the button back" branch in [onCaptured] saw no active
     * job and re-enabled "Take shot" between shots. Pressing it then ran a *second*
     * sequence against the same camera. On hardware 2026-08-18 that produced a 4-shot strip
     * whose shutters fired 50ms after the previous shot with the countdowns landing after
     * the exposures, and a fifth frame taken 22ms after the session had already reported
     * `completed (4 shots)`.
     */
    private fun startShotSequence() {
        if (captureJob?.isActive == true) return
        shutterButton.isEnabled = false
        captureJob = scope.launch { runShotSequence() }
    }

    /**
     * Ignores the SharedFlow replay from the previous capture session.
     *
     * [consumedHandles] stops a shot completing twice *within* one session, but the queue
     * outlives this Activity — it belongs to [CameraSessionManager] — while the set does
     * not. So a second POSE session started with an empty set and was handed the previous
     * session's last photo the instant it collected, completing its first shot in
     * milliseconds with a picture of whoever posed before.
     *
     * Observed on hardware 2026-08-18: a 4-shot strip finished `0004_IMG_8262.JPG`, and the
     * next session's log read `Shot 1/4 stored: 0004_IMG_8262.JPG` — the same file. That is
     * the "old picture on the preview screen" the booth was showing guests.
     *
     * See [CaptureQueue.seedReplayInto] — without this, Back → POSE → shutter returns
     * the last shot's file before the new release finishes.
     */
    private fun seedStaleCaptureReplay() {
        CameraSessionManager.captureQueue?.seedReplayInto(consumedHandles)
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

        seedStaleCaptureReplay()

        // Subscribe BEFORE firing, and UNDISPATCHED so the collector is attached before
        // this line returns. A download can finish faster than a coroutine scheduled the
        // ordinary way would take to start collecting, and the event would be missed.
        val done = scope.async(start = CoroutineStart.UNDISPATCHED) {
            queue.completed.first { it.handle !in consumedHandles }
        }

        // Wait for the shutter to actually fire before waiting for an image. A release that
        // comes back DeviceBusy produces no photo, and treating that as "in flight" cost the
        // full CAPTURE_TIMEOUT_MS of blank screen per failed attempt — two in a row put a
        // guest through 106s of nothing before the third try worked (hardware 2026-08-18).
        if (!CameraSessionManager.triggerCapture(withAutofocus = true).await()) {
            done.cancel()
            setStatus(getString(R.string.canon_status_capture_failed))
            shutterButton.isEnabled = !request.autoStart
            CanonLog.e("Shutter did not fire; not waiting for an image")
            return false
        }

        val completed = withTimeoutOrNull(CAPTURE_TIMEOUT_MS) { done.await() }
        done.cancel()

        if (completed == null) {
            setStatus(getString(R.string.canon_status_capture_failed))
            shutterButton.isEnabled = !request.autoStart
            CanonLog.e("Capture timed out after %dms", CAPTURE_TIMEOUT_MS)
            return false
        }

        consumedHandles += completed.handle
        val isLastCapture = capturesCompleted + 1 >= request.shotCount
        capturesCompleted++

        // Derivative + thumbnail run off the critical path so rearrange / countdown can
        // start immediately. The final shot must finish before Flutter receives paths.
        val derivativeJob = scope.async(Dispatchers.Default) {
            processCapturedShot(completed, showProcessingStatus = isLastCapture)
        }
        derivativeJobs += derivativeJob
        if (isLastCapture) {
            derivativeJob.await()
            derivativeJobs.clear()
        }
        return true
    }

    private suspend fun processCapturedShot(
        done: CaptureQueue.Item.Done,
        showProcessingStatus: Boolean,
    ) {
        if (showProcessingStatus) {
            withContext(Dispatchers.Main.immediate) {
                setStatus(getString(R.string.canon_status_processing))
            }
        }

        val original = done.image.file
        val derivative = DisplayDerivative.create(
            original = original,
            maxLongEdge = request.displayMaxLongEdge,
            jpegQuality = request.displayJpegQuality,
        )

        withContext(Dispatchers.Main.immediate) {
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

            addThumbnail(derivative?.thumbnailBitmap)

            // A landed shot is proof the guest is still there, so the idle clock starts over.
            startIdleWatchdog()

            if (shots.size >= request.shotCount) {
                finishWith(
                    CaptureSessionContract.Result(
                        status = CaptureSessionContract.STATUS_COMPLETED,
                        shots = shots.toList(),
                    ),
                )
            } else if (captureJob?.isActive != true) {
                // Only hand the button back when nothing is driving the strip. Keyed on the job
                // rather than on autoStart because runShotSequence continues straight into the
                // next countdown, and re-enabling mid-strip would offer a press that does nothing.
                setStatus(
                    getString(R.string.canon_status_ready_format, shots.size + 1, request.shotCount),
                )
                shutterButton.isEnabled = true
            }
        }
    }

    /**
     * Adds the shot to the strip so guests can see the set building.
     *
     * Uses the in-memory thumbnail from [DisplayDerivative] — no second file decode.
     */
    private fun addThumbnail(bitmap: Bitmap?) {
        if (bitmap == null || request.shotCount <= 1) return

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

        const val THUMBNAIL_WIDTH_PX = 150
        const val THUMBNAIL_GAP_PX = 12

        /**
         * Shutter to image-on-disk.
         *
         * Wide because the body can answer `DeviceBusy` for ~8s after a release while the
         * image is still in its buffer (`P-18`), and the download itself follows.
         */
        const val CAPTURE_TIMEOUT_MS = 45_000L

        /** Matches the Flutter capture bar, which greys unavailable actions rather than hiding them. */
        const val DISABLED_ACTION_ALPHA = 0.4f
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
