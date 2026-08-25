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
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    private lateinit var shotCapture: CanonShotCapture
    private lateinit var countdown: CanonCountdown
    private lateinit var thumbStrip: CanonThumbStrip
    private lateinit var connector: CanonCaptureConnector
    private lateinit var uploadViews: CanonUploadViews
    private lateinit var uploadActions: CanonUploadActions
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

        request =
            CaptureSessionContract.Request.fromJson(
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
        shotReview =
            CanonShotReview(
                views = CanonReviewViews(reviewStill, reviewBanner, retakeButton, shutterButton),
                actions =
                    CanonReviewActions(
                        resolve = { id, args -> resolveReviewString(id, args) },
                        isFinished = { finished },
                        isUiAlive = { isCaptureUiAlive() },
                        clearStatus = { if (isCaptureUiAlive()) clearStatus() },
                        restoreShutter = { if (isCaptureUiAlive()) restoreShutterForCapture() },
                    ),
            )
        thumbStrip =
            CanonThumbStrip(
                strip = thumbnailStrip,
                inflater = layoutInflater,
                density = resources.displayMetrics.density,
            )
        thumbStrip.buildSlots(request.shotCount)
        countdown =
            CanonCountdown(
                views =
                    CanonCountdownViews(
                        countdownText,
                        countdownHeadline,
                        countdownScrim,
                        countdownGroup,
                    ),
                actions =
                    CanonCountdownActions(
                        isFinished = { finished },
                        setStatus = { setStatus(it) },
                        beep = { beep() },
                        introText = { getString(R.string.canon_countdown_intro) },
                        poseStatus = { shot, total ->
                            getString(R.string.canon_status_pose_format, shot, total)
                        },
                    ),
            )
        shotCapture =
            CanonShotCapture(
                scope = scope,
                shots = shots,
                consumedHandles = consumedHandles,
                host = shotCaptureHost(),
            )
        connector =
            CanonCaptureConnector(
                appContext = applicationContext,
                host =
                    object : CanonCaptureConnector.Host {
                        override val isFinished: Boolean get() = finished

                        override fun finishWith(result: CaptureSessionContract.Result) = this@CanonCaptureActivity.finishWith(result)
                    },
            )
        uploadViews = CanonUploadViews(galleryButton, phoneQrButton)
        uploadActions =
            CanonUploadActions(
                allowGallery = { request.allowGalleryUpload },
                allowPhone = { request.allowPhoneUpload },
                beforeFirstShot = { shots.isEmpty() },
                finishWith = { finishWith(it) },
            )
        CanonCaptureChrome.bindUploads(uploadViews, uploadActions)

        toneGenerator =
            runCatching {
                ToneGenerator(AudioManager.STREAM_MUSIC, TONE_VOLUME)
            }.getOrNull()
        shutterSound =
            runCatching { MediaActionSound().apply { load(MediaActionSound.SHUTTER_CLICK) } }
                .getOrNull()

        request.titleText?.let { titleText.text = it }
        // Booth layout only; the diagnostic one has no subtitle line.
        request.subtitleText?.let {
            findViewById<TextView?>(R.id.canon_subtitle)?.text = it
        }
        request.shutterText?.let { shutterButton.text = it }
        request.cancelText?.let { cancelButton.text = it }

        shutterButton.setOnClickListener { onShutter() }
        val cancel =
            View.OnClickListener {
                finishWith(CaptureSessionContract.Result.cancelled("Cancelled by user"))
            }
        cancelButton.setOnClickListener(cancel)
        // Present only in the booth layout, mirroring the Flutter capture bar's back arrow.
        findViewById<View?>(R.id.canon_back)?.setOnClickListener(cancel)
        CanonCaptureChrome.bindTopBar(
            views =
                CanonTopBarViews(
                    reconnect = findViewById(R.id.canon_reconnect),
                    selectCamera = findViewById(R.id.canon_select_camera),
                    rotate = findViewById(R.id.canon_rotate),
                ),
            actions =
                CanonTopBarActions(
                    isCapturing = { captureJob?.isActive == true },
                    onReconnect = {
                        setStatus(getString(R.string.canon_status_reconnecting))
                        CanonLog.i("Operator asked for a reconnect from the capture screen")
                        CameraSessionManager.scanAndConnect(applicationContext)
                    },
                    disabledAlpha = DISABLED_ACTION_ALPHA,
                ),
        )
        // The box reports touch AND d-pad; the shutter must be reachable without a screen tap.
        shutterButton.requestFocus()

        renderer = LiveViewSurfaceRenderer(surface.holder)
        surface.holder.addCallback(
            object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    renderer?.isSurfaceReady = true
                }

                override fun surfaceChanged(
                    holder: SurfaceHolder,
                    f: Int,
                    w: Int,
                    h: Int,
                ) = Unit

                override fun surfaceDestroyed(holder: SurfaceHolder) {
                    // Must clear before returning, or the render loop draws into a dead surface.
                    renderer?.isSurfaceReady = false
                }
            },
        )

        startSession()
    }

    // ------------------------------------------------------------------ session

    private fun startSession() {
        scope.launch {
            setStatus(getString(R.string.canon_status_connecting))

            if (!connector.ensureConnected()) return@launch

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
        idleJob =
            scope.launch {
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

            countdown.run(shotNumber, request)
            if (finished) return

            val ok = shotCapture.runOneShot()
            if (!ok) {
                // A failed shot is retried rather than abandoning the strip — the guest is
                // still standing there, and losing three good shots to one bad one is worse
                // than an extra countdown.
                setStatus(getString(R.string.canon_status_capture_failed))
                delay(RETRY_PAUSE_MS)
                continue
            }

            // A shot has landed, so the upload alternatives go.
            CanonCaptureChrome.refreshUploads(uploadViews, uploadActions)

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
        CanonCaptureChrome.refreshUploads(uploadViews, uploadActions)
    }

    /** Puts the primary button back to its "Take shot" identity after a review. */
    private fun restoreShutterForCapture() {
        shutterButton.setOnClickListener { onShutter() }
        shutterButton.text = request.shutterText ?: getString(R.string.canon_capture_shutter)
        shutterButton.setCompoundDrawablesRelativeWithIntrinsicBounds(
            R.drawable.ic_canon_shutter,
            0,
            0,
            0,
        )
        shutterButton.isEnabled = false
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

    private fun shotCaptureHost(): CanonShotCapture.Host =
        object : CanonShotCapture.Host {
            override val request: CaptureSessionContract.Request
                get() = this@CanonCaptureActivity.request

            override fun string(
                id: Int,
                vararg args: Any,
            ): String = if (args.isEmpty()) getString(id) else getString(id, *args)

            override fun setStatus(text: String) = this@CanonCaptureActivity.setStatus(text)

            override fun finishWith(result: CaptureSessionContract.Result) = this@CanonCaptureActivity.finishWith(result)

            override fun startIdleWatchdog() = this@CanonCaptureActivity.startIdleWatchdog()

            override fun fillThumb(
                shotsTaken: Int,
                thumbnail: Bitmap?,
            ) {
                if (::thumbStrip.isInitialized) thumbStrip.fillSlot(shotsTaken, thumbnail)
            }

            override fun setShutterEnabled(enabled: Boolean) {
                shutterButton.isEnabled = enabled
            }

            override fun isCaptureJobActive(): Boolean = captureJob?.isActive == true

            override fun isUiAlive(): Boolean = isCaptureUiAlive()

            override fun playShutterSound() = shutterSound()

            override fun seedStaleReplay() = seedStaleCaptureReplay()
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

    private fun resolveReviewString(
        id: Int,
        args: Array<out Any>,
    ): String {
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
        const val BEEP_MS = 150
        const val TONE_VOLUME = 80

        /** Pause after a failed shot before retrying, so the body can settle. */
        const val RETRY_PAUSE_MS = 1_500L

        /** Matches the Flutter capture bar, which greys unavailable actions rather than hiding them. */
        const val DISABLED_ACTION_ALPHA = 0.4f
    }
}
