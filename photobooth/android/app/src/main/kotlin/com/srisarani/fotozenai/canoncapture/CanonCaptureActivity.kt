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
    private lateinit var countdownHeadline: TextView
    private lateinit var countdownScrim: View
    private lateinit var countdownGroup: View
    private lateinit var thumbnailStrip: LinearLayout
    private lateinit var shutterButton: Button
    private lateinit var cancelButton: Button
    private lateinit var retakeButton: Button
    private lateinit var galleryButton: Button
    private lateinit var phoneQrButton: Button
    private lateinit var reviewStill: ImageView
    private lateinit var reviewBanner: TextView

    private var renderer: LiveViewSurfaceRenderer? = null
    private lateinit var shotReview: CanonShotReview
    private lateinit var thumbStrip: CanonThumbStrip
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
        countdownHeadline = findViewById(R.id.canon_countdown_headline)
        countdownScrim = findViewById(R.id.canon_countdown_scrim)
        countdownGroup = findViewById(R.id.canon_countdown_group)
        thumbnailStrip = findViewById(R.id.canon_thumbnails)
        shutterButton = findViewById(R.id.canon_shutter)
        cancelButton = findViewById(R.id.canon_cancel)
        retakeButton = findViewById(R.id.canon_retake)
        galleryButton = findViewById(R.id.canon_gallery)
        phoneQrButton = findViewById(R.id.canon_phone_qr)
        reviewStill = findViewById(R.id.canon_review_still)
        reviewBanner = findViewById(R.id.canon_review_banner)
        shotReview = CanonShotReview(
            views = CanonReviewViews(reviewStill, reviewBanner, retakeButton, shutterButton),
            actions = CanonReviewActions(
                resolve = { id, args -> resolveReviewString(id, args) },
                isFinished = { finished },
                isUiAlive = { isCaptureUiAlive() },
                clearStatus = { if (isCaptureUiAlive()) clearStatus() },
                restoreShutter = { if (isCaptureUiAlive()) restoreShutterForCapture() },
            ),
        )
        thumbStrip = CanonThumbStrip(
            strip = thumbnailStrip,
            inflater = layoutInflater,
            density = resources.displayMetrics.density,
        )
        thumbStrip.buildSlots(request.shotCount)
        bindUploadActions()

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
        while (shots.size < request.shotCount && !finished) {
            val shotNumber = shots.size + 1

            runCountdown(shotNumber)
            if (finished) return

            val ok = runOneShot()
            if (!ok) {
                // A failed shot is retried rather than abandoning the strip — the guest is
                // still standing there, and losing three good shots to one bad one is worse
                // than an extra countdown.
                setStatus(getString(R.string.canon_status_capture_failed))
                delay(RETRY_PAUSE_MS)
                continue
            }

            // A shot has landed, so the upload alternatives go.
            refreshUploadActions()

            // Review the still just taken. This replaces the old holdForRearrange, which ran
            // *before* the next countdown and showed live view — so the guest was told to
            // rearrange while watching themselves move, never seeing the shot. Flutter holds
            // on the captured photo instead, which is what this does.
            if (shotReview.present(request, shots) == ReviewOutcome.RETAKE) {
                dropLastShot()
            }
        }

        if (!finished) {
            finishWith(
                CaptureSessionContract.Result(
                    status = CaptureSessionContract.STATUS_COMPLETED,
                    shots = shots.toList(),
                ),
            )
        }
    }

    /**
     * Offers Gallery / Phone QR when the kiosk allows them, and hands the choice to Dart.
     *
     * Neither upload happens here. Phone QR needs `/api/kiosk/upload-links` and a poll loop,
     * and Gallery is a single `viewModel.selectFromGallery()` on the Dart side — both already
     * exist for the Flutter capture screen. Duplicating them natively would mean two
     * implementations free to drift, so the Activity ends the session with
     * [CaptureSessionContract.STATUS_UPLOAD_REQUESTED] and lets Dart run the code it has.
     *
     * Cost of that choice: leaving the Activity tears down live view, so returning from a
     * cancelled sheet reconnects the camera — a visible blink the Flutter screen does not
     * have. Accepted deliberately; keeping the Activity alive behind a Dart overlay is much
     * more machinery for a transition most guests will not see twice.
     *
     * Visibility is [refreshUploadActions]' job — they stay up through the first countdown
     * and go once a shot actually lands.
     */
    private fun bindUploadActions() {
        refreshUploadActions()
        galleryButton.setOnClickListener {
            finishWith(
                CaptureSessionContract.Result.uploadRequested(
                    CaptureSessionContract.UPLOAD_SOURCE_GALLERY,
                ),
            )
        }
        phoneQrButton.setOnClickListener {
            finishWith(
                CaptureSessionContract.Result.uploadRequested(
                    CaptureSessionContract.UPLOAD_SOURCE_PHONE,
                ),
            )
        }
    }

    /**
     * Uploads are offered only until the first shot lands.
     *
     * Mirrors `capturePhotoUploadActionsAllowed`, whose gate is
     * `classicFourShotInProgress = isClassicFourShot && _stripShots.isNotEmpty` — so they
     * *are* offered on a 4-shot strip, but only before shot 1, because "a gallery pick
     * cannot break strip indexing / remount" once the set has started.
     *
     * Keyed on `shots` rather than on the sequence having started, so they stay up through
     * the first countdown exactly as they do on the Flutter screen, and come back if a
     * retake empties the strip again.
     */
    private fun refreshUploadActions() {
        val beforeFirstShot = shots.isEmpty()
        galleryButton.visibility =
            if (request.allowGalleryUpload && beforeFirstShot) View.VISIBLE else View.GONE
        phoneQrButton.visibility =
            if (request.allowPhoneUpload && beforeFirstShot) View.VISIBLE else View.GONE
    }

    /**
     * Discards the shot under review so the loop shoots that slot again.
     *
     * The original and its derivative are left on disk. They are in the session directory,
     * which is cleaned as a whole, and deleting a file the download queue may still hold a
     * handle to is not worth the risk for a few MB.
     */
    private fun dropLastShot() {
        if (shots.isEmpty()) return
        val dropped = shots.removeAt(shots.lastIndex)
        CanonLog.i("Retake: dropped shot %d (%s)", shots.size + 1, dropped.originalPath)
        // Empty the slot rather than removing it: the strip is a fixed set of poses, and
        // dropping a view would shrink it, making a 4-shot strip look like a 3-shot one.
        if (::thumbStrip.isInitialized) {
            thumbStrip.clearAt(shots.size, shots.size)
        }
        refreshUploadActions()
    }

    /** Puts the primary button back to its "Take shot" identity after a review. */
    private fun restoreShutterForCapture() {
        shutterButton.setOnClickListener { onShutter() }
        shutterButton.text = request.shutterText ?: getString(R.string.canon_capture_shutter)
        shutterButton.setCompoundDrawablesRelativeWithIntrinsicBounds(
            R.drawable.ic_canon_shutter, 0, 0, 0,
        )
        shutterButton.isEnabled = false
    }

    private suspend fun runCountdown(shotNumber: Int) {
        // FotoZen only, and only on the first tick: Classic already says "shot X of Y" in the
        // subtitle and the status line, so repeating it over the preview is noise.
        // Mirrors `showAiIntro` in _buildCountdownOverlay.
        val showHeadline = request.showCountdownHeadline
        countdownHeadline.text = getString(R.string.canon_countdown_intro)

        for (remaining in request.countdownSeconds downTo 1) {
            if (finished) return
            countdownScrim.visibility = View.VISIBLE
            countdownGroup.visibility = View.VISIBLE
            countdownHeadline.visibility =
                if (showHeadline && remaining == request.countdownSeconds) {
                    View.VISIBLE
                } else {
                    View.GONE
                }
            countdownText.visibility = View.VISIBLE
            countdownText.text = remaining.toString()
            setStatus(
                getString(R.string.canon_status_pose_format, shotNumber, request.shotCount),
            )
            if (remaining <= COUNTDOWN_BEEP_FROM) beep()
            delay(1000)
        }
        hideCountdown()
    }

    private fun hideCountdown() {
        countdownText.visibility = View.GONE
        countdownHeadline.visibility = View.GONE
        countdownGroup.visibility = View.GONE
        countdownScrim.visibility = View.GONE
    }

    /** Connects if needed; finishes the Activity with a typed error if it cannot. */
    private suspend fun ensureConnected(): Boolean {
        if (CanonCaptureConnect.isReady(CameraSessionManager.state.value)) return true

        if (CanonCaptureConnect.isStalePtpSession(CameraSessionManager.state.value)) {
            CameraSessionManager.disconnectAndAwait()
        }

        repeat(2) { attempt ->
            CameraSessionManager.scanAndConnect(applicationContext)
            // drop(1) discards the value the StateFlow replays on subscription — the state as
            // it was *before* the scan above could change it. Without it this whole wait
            // collapsed: the manager sits at ConnectionState.NoDevice, isConnectOutcome()
            // counts NoDevice as terminal, so `first` matched that stale value immediately and
            // POSE reported "No camera found" roughly 90ms in — while the very same connect
            // went on to succeed seconds later. Observed on hardware 2026-08-18.
            val settled = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
                CameraSessionManager.state.drop(1).first {
                    CanonCaptureConnect.isConnectOutcome(it) || CanonCaptureConnect.isReady(it)
                }
            }

            val state = settled ?: CameraSessionManager.state.value
            if (CanonCaptureConnect.isReady(state)) return true
            val error = CanonCaptureConnect.errorResult(state)
            if (error != null) {
                finishWith(error)
            } else if (attempt == 0) {
                CanonLog.w("Connect attempt ${attempt + 1} stalled at $state — retrying")
                CameraSessionManager.disconnectAndAwait()
                delay(RETRY_PAUSE_MS)
            } else {
                finishWith(
                    CaptureSessionContract.Result.error(
                        CaptureSessionContract.ERROR_CONNECT_FAILED,
                        CanonCaptureConnect.describe(state),
                    ),
                )
            }
            if (finished) return false
        }
        return false
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
        val isLastCapture = shots.size + 1 >= request.shotCount

        // Off the main thread, but **awaited** — the one place this merge could not keep
        // main's shape.
        //
        // origin/main fires the derivative as a detached `scope.async` and only awaits it on
        // the final shot, to "overlap native display derivatives with rearrange". That
        // overlap has nothing left to overlap with: the rearrange window is now the review,
        // and the review *shows the still*, so its derivative is needed immediately rather
        // than at leisure. Leaving it detached meant `shots` was still empty when
        // reviewLastShot() read it, so the guest reviewed a blank card.
        //
        // Awaiting also removes the `capturesCompleted` counter main added to track "USB
        // done, derivative maybe not". With the await, `shots.size` is authoritative again —
        // which retake needs, because dropLastShot() shrinks `shots` and a separate counter
        // would drift from it and mis-terminate the strip.
        //
        // The decode still runs on Dispatchers.Default, so the viewfinder does not stutter;
        // the cost is ~250ms before the still appears, which is not perceptible.
        withContext(Dispatchers.Default) {
            processCapturedShot(completed, showProcessingStatus = isLastCapture)
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
            if (!isCaptureUiAlive()) return@withContext
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

            if (::thumbStrip.isInitialized) {
                thumbStrip.fillSlot(shots.size, derivative?.thumbnailBitmap)
            }

            // A landed shot is proof the guest is still there, so the idle clock starts over.
            startIdleWatchdog()

            // Deliberately does NOT finish the session on the last shot.
            //
            // [runShotSequence] owns completion, because the final still has to sit in
            // review first with Retake and "Pick a look" available. Finishing here returned
            // to Dart the instant the shot landed, so the guest never saw their last shot
            // and could not retake it.
            if (shots.size < request.shotCount && captureJob?.isActive != true) {
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

    private fun isCaptureUiAlive(): Boolean = !isFinishing && !isDestroyed

    private fun resolveReviewString(id: Int, args: Array<out Any>): String {
        if (!isCaptureUiAlive()) return ""
        return if (args.isEmpty()) getString(id) else getString(id, *args)
    }

    private fun setStatus(text: String) {
        if (!isCaptureUiAlive()) return
        statusText.text = text
        statusText.visibility = View.VISIBLE
    }

    /**
     * Hides the progress line.
     *
     * GONE rather than blank so the review buttons take back the vertical space instead of
     * sitting under an empty gap — [setStatus] flips it back on for the next countdown.
     */
    private fun clearStatus() {
        if (!isCaptureUiAlive()) return
        statusText.text = ""
        statusText.visibility = View.GONE
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 30_000L

        /** Beep only on the closing seconds — a beep every second for 10s is irritating. */
        const val COUNTDOWN_BEEP_FROM = 3
        const val BEEP_MS = 150
        const val TONE_VOLUME = 80

        /** Pause after a failed shot before retrying, so the body can settle. */
        const val RETRY_PAUSE_MS = 1_500L

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
