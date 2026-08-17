package com.srisarani.fotozenai.canoncapture

import android.app.Activity
import android.graphics.Bitmap
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import com.srisarani.fotozenai.R
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureQueue
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import com.srisarani.fotozenai.canon.state.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
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
    private lateinit var shutterButton: Button
    private lateinit var cancelButton: Button

    private var renderer: LiveViewSurfaceRenderer? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var request = CaptureSessionContract.Request()

    private val shots = mutableListOf<CaptureSessionContract.Shot>()
    private var captureJob: Job? = null
    private var finished = false

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
        setContentView(R.layout.activity_canon_capture)

        request = CaptureSessionContract.Request.fromJson(
            intent.getStringExtra(CaptureSessionContract.EXTRA_REQUEST),
        )

        surface = findViewById(R.id.canon_live_view)
        statusText = findViewById(R.id.canon_status)
        titleText = findViewById(R.id.canon_title)
        shutterButton = findViewById(R.id.canon_shutter)
        cancelButton = findViewById(R.id.canon_cancel)

        request.titleText?.let { titleText.text = it }
        request.shutterText?.let { shutterButton.text = it }
        request.cancelText?.let { cancelButton.text = it }

        shutterButton.setOnClickListener { onShutter() }
        cancelButton.setOnClickListener {
            finishWith(CaptureSessionContract.Result.cancelled("Cancelled by user"))
        }
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
            setStatus(
                getString(R.string.canon_status_ready_format, shots.size + 1, request.shotCount),
            )
            shutterButton.isEnabled = true
        }
    }

    /** Connects if needed; finishes the Activity with a typed error if it cannot. */
    private suspend fun ensureConnected(): Boolean {
        if (CameraSessionManager.state.value.isReadyForCapture()) return true

        CameraSessionManager.scanAndConnect(applicationContext)
        val settled = withTimeoutOrNull(CONNECT_TIMEOUT_MS) {
            CameraSessionManager.state.first { it.isConnectOutcome() }
        }

        when (settled) {
            is ConnectionState.Ready, is ConnectionState.RemoteMode -> return true
            is ConnectionState.PermissionDenied -> finishWith(
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_PERMISSION_DENIED,
                    "USB permission was refused for the camera",
                ),
            )

            is ConnectionState.NoDevice, null -> finishWith(
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

            else -> finishWith(
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_CONNECT_FAILED,
                    describe(settled),
                ),
            )
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
            liveView.currentFrame.collect { frame: Bitmap? ->
                if (frame != null) {
                    withContext(Dispatchers.Default) { renderer?.draw(frame) }
                }
            }
        }
    }

    // ------------------------------------------------------------------ capture

    private fun onShutter() {
        if (captureJob?.isActive == true) return
        shutterButton.isEnabled = false
        captureJob = scope.launch { runOneShot() }
    }

    private suspend fun runOneShot() {
        val queue = CameraSessionManager.captureQueue
        if (queue == null) {
            finishWith(
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_CAPTURE_FAILED,
                    "Capture queue unavailable — the camera session is not fully open",
                ),
            )
            return
        }

        setStatus(getString(R.string.canon_status_capturing))

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
            shutterButton.isEnabled = true
            CanonLog.e("Capture timed out after %dms", CAPTURE_TIMEOUT_MS)
            return
        }

        consumedHandles += completed.handle
        onCaptured(completed)
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

        if (shots.size >= request.shotCount) {
            finishWith(
                CaptureSessionContract.Result(
                    status = CaptureSessionContract.STATUS_COMPLETED,
                    shots = shots.toList(),
                ),
            )
        } else {
            setStatus(
                getString(R.string.canon_status_ready_format, shots.size + 1, request.shotCount),
            )
            shutterButton.isEnabled = true
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
        scope.cancel()
        super.onDestroy()
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

        /**
         * Shutter to image-on-disk.
         *
         * Wide because the body can answer `DeviceBusy` for ~8s after a release while the
         * image is still in its buffer (`P-18`), and the download itself follows.
         */
        const val CAPTURE_TIMEOUT_MS = 45_000L
    }
}

private fun ConnectionState.isReadyForCapture(): Boolean =
    this is ConnectionState.Ready ||
        this is ConnectionState.RemoteMode ||
        this is ConnectionState.LiveView

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
