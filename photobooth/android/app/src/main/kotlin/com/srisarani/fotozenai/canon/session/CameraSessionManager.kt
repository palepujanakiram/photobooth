package com.srisarani.fotozenai.canon.session

import android.content.Context
import android.hardware.usb.UsbDevice
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureQueue
import com.srisarani.fotozenai.canon.capture.ImageStore
import com.srisarani.fotozenai.canon.eos.EosCameraSettings
import com.srisarani.fotozenai.canon.eos.EosCapture
import com.srisarani.fotozenai.canon.eos.EosLiveView
import com.srisarani.fotozenai.canon.eos.EosProperties
import com.srisarani.fotozenai.canon.eos.EosSession
import com.srisarani.fotozenai.canon.ptp.PtpDeviceInfo
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpSession
import com.srisarani.fotozenai.canon.state.ConnectionState
import com.srisarani.fotozenai.canon.state.isReadyForCapture
import com.srisarani.fotozenai.canon.state.label
import com.srisarani.fotozenai.canon.usb.UsbCameraDiscovery
import com.srisarani.fotozenai.canon.usb.UsbError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

/**
 * Process-wide owner of the camera connection.
 *
 * A singleton rather than an injected dependency because Track A bans a DI framework, and
 * because the connection genuinely is process-scoped: it must outlive the Activity (U-04)
 * and be reachable from both the foreground service and the view model.
 *
 * ## The threading rule (plan section 3)
 *
 * Every byte of USB I/O goes through [usbDispatcher], which is backed by exactly one
 * thread. PTP is a strictly serialised request/response protocol with a monotonic
 * transaction ID; two coroutines touching the endpoint concurrently corrupt the session
 * and surface as InvalidTransactionID errors that look like protocol bugs (P-02).
 *
 * This is not a performance tuning decision that can be revisited later. It is a
 * correctness requirement of the protocol.
 */
object CameraSessionManager {
    private val usbThread =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "usb-io").apply { isDaemon = true }
        }

    /** The one and only thread permitted to touch the USB endpoints. */
    val usbDispatcher = usbThread.asCoroutineDispatcher()

    private val scope = CoroutineScope(SupervisorJob() + usbDispatcher)

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.NoDevice)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    @Volatile
    private var opened: UsbCameraDiscovery.OpenedCamera? = null

    /** The live PTP session, or null when disconnected. */
    @Volatile
    var session: PtpSession? = null
        private set

    /** The live EOS remote-mode session, or null. M4 consumes its event stream. */
    @Volatile
    var eosSession: EosSession? = null
        private set

    @Volatile
    var eosCapture: EosCapture? = null
        private set

    @Volatile
    var captureQueue: CaptureQueue? = null
        private set

    /** Set from the service, which owns a Context. */
    @Volatile
    var imageStore: ImageStore? = null

    @Volatile
    var liveView: EosLiveView? = null
        private set

    /** Live camera settings, built from the event stream (`P-12`). */
    @Volatile
    var cameraSettings: EosCameraSettings? = null
        private set

    /** Applies a property change on the USB thread. */
    fun stepSetting(
        propertyCode: Int,
        table: Map<Int, String>,
        forward: Boolean,
    ) {
        scope.launch {
            cameraSettings?.step(propertyCode, table, forward)
        }
    }

    /**
     * Fires the shutter.
     *
     * Returns immediately: the image arrives asynchronously via the event loop and is
     * pulled by [CaptureQueue]. Blocking here would serialise shutter and transfer.
     *
     * ## C-13: live view and still capture must be sequenced
     *
     * On EOS bodies a still capture with live view running is unreliable, and the first
     * frames after it resumes are garbage. So live view is stopped before the release and
     * restarted afterwards, rather than left running and hoped for.
     *
     * ## C-16: live view must stay down until the image is *downloaded*, not just shot
     *
     * Observed on hardware 2026-08-14: resuming live view on a fixed timer after the
     * release starved the download. Live view targets one frame every few milliseconds on
     * the same single USB thread, so it saturates the endpoint before `ObjectAdded` even
     * arrives. The image then sits in the camera's buffer, the body reports `DeviceBusy`
     * for everything (it stays busy until its buffer drains), and the capture never
     * completes — the queue shows "no captures yet" while the shutter clearly fired.
     *
     * So the resume waits for the queue to finish the transfer. [CAPTURE_DRAIN_TIMEOUT_MS]
     * bounds it: a lost image must not leave the booth without a viewfinder.
     *
     * @return completes with whether the shutter actually fired, as soon as that is known.
     *   The download still finishes asynchronously — that is the point of this method — but
     *   the *release* outcome has to be reachable by the caller. It used to be swallowed
     *   here, so a `RemoteReleaseOn` answering `DeviceBusy` looked identical to a shot in
     *   flight, and the capture screen sat out its full 45s image timeout waiting for a
     *   photo that was never taken. On hardware 2026-08-18 two failed releases in a row cost
     *   the guest 106 seconds of blank screen before the third attempt worked.
     */
    fun triggerCapture(withAutofocus: Boolean = true): Deferred<Boolean> {
        val released = CompletableDeferred<Boolean>()
        scope
            .launch {
                val capture = eosCapture
                if (capture == null) {
                    CanonLog.w("Capture requested but no EOS session is active")
                    released.complete(false)
                    return@launch
                }

                val liveViewWasRunning = pauseLiveViewForCapture()

                val fired =
                    runCatching {
                        val mode =
                            if (withAutofocus) {
                                EosCapture.ReleaseMode.WITH_AUTOFOCUS
                            } else {
                                EosCapture.ReleaseMode.WITHOUT_AUTOFOCUS
                            }
                        capture.release(mode)
                    }.onFailure { CanonLog.e(it, "Shutter release failed") }.isSuccess

                // Publish before draining, not after: the caller needs to stop waiting for an
                // image the moment we know none is coming, and awaitCaptureDrained below can
                // itself take seconds.
                released.complete(fired)

                // C-16: hold live view down until the bytes are safely on disk.
                if (fired) CameraSessionHandshake.awaitCaptureDrained(captureQueue)
                resumeLiveViewAfterCapture(liveViewWasRunning)
            }.invokeOnCompletion { cause ->
                // A cancelled or crashed launch must not leave the caller awaiting forever.
                if (!released.isCompleted) released.complete(false)
                if (cause != null) CanonLog.w(cause, "Capture coroutine ended before releasing")
            }
        return released
    }

    private suspend fun pauseLiveViewForCapture(): Boolean {
        val running = liveView?.isRunning?.value == true
        if (!running) return false
        CanonLog.d("Pausing live view for capture (C-13)")
        liveView?.stop()
        // Stopping live view is asynchronous inside the camera. An instant RemoteReleaseOn
        // arrives while the body still considers itself busy (hardware 2026-08-17).
        kotlinx.coroutines.delay(LIVE_VIEW_SETTLE_BEFORE_RELEASE_MS)
        return true
    }

    private suspend fun resumeLiveViewAfterCapture(wasRunning: Boolean) {
        if (!wasRunning) return
        kotlinx.coroutines.delay(LIVE_VIEW_RESUME_DELAY_MS)
        liveView?.start()
    }

    fun toggleLiveView() {
        scope.launch {
            val lv = liveView ?: return@launch
            if (lv.isRunning.value) lv.stop() else lv.start()
        }
    }

    /** The live transport, or null when disconnected. */
    val transport get() = opened?.transport

    /**
     * Where capability dumps are written. Set once from the service, because the manager
     * is a singleton with no Context of its own and should not hold one.
     */
    @Volatile
    var capabilityDumpDir: java.io.File? = null

    // ------------------------------------------------------------------ scan

    /**
     * Looks for a camera and connects to it if permission allows.
     *
     * Safe to call repeatedly - reconnect attempts, manual rescans and attach broadcasts
     * all funnel through here.
     */
    fun scanAndConnect(context: Context) {
        scope.launch { scanAndConnectInternal(context.applicationContext) }
    }

    private suspend fun scanAndConnectInternal(context: Context) {
        val discovery = UsbCameraDiscovery(context)

        if (!discovery.isUsbHostSupported) {
            CanonLog.e("No UsbManager: this device cannot host USB (U-07)")
            _state.value = ConnectionState.NoUsbHostSupport
            return
        }

        if (opened != null) {
            if (_state.value.isReadyForCapture) {
                CanonLog.d("scanAndConnect ignored - already connected")
                return
            }
            // Device open but not ready: a previous openPtpSession failed after the
            // interface was already claimed. Returning here would make every later retry -
            // including the operator pressing "Try again" - a no-op, which is what left the
            // booth needing a replug or an app restart to recover (observed 2026-08-18).
            // Keyed off state rather than `session != null` because a session object can
            // outlive a handshake that never reached remote mode.
            CanonLog.w(
                "scanAndConnect clearing stale session (state=%s)",
                _state.value.label,
            )
            releaseQuietly()
        }

        // Publish before looking. See ConnectionState.Scanning: without a distinct value
        // here, a scan that finds nothing sets NoDevice over NoDevice, which StateFlow
        // conflates away, and every caller waiting for the outcome waits for its timeout.
        _state.value = ConnectionState.Scanning

        discovery.logAttachedDevices()
        val cameras = discovery.findCameras()

        if (cameras.isEmpty()) {
            _state.value = ConnectionState.NoDevice
            return
        }

        val device = cameras.first()
        if (cameras.size > 1) {
            CanonLog.w("%d cameras attached; using %s", cameras.size, device.deviceName)
        }

        _state.value =
            ConnectionState.DeviceFound(
                deviceName = device.deviceName,
                productName = device.productName,
                vendorId = device.vendorId,
                productId = device.productId,
                permissionPending = !discovery.hasPermission(device),
            )

        if (!discovery.hasPermission(device)) {
            CanonLog.i("Requesting USB permission for %s", device.deviceName)
            val granted = discovery.requestPermission(device)
            if (!granted) {
                _state.value = ConnectionState.PermissionDenied(device.deviceName)
                return
            }
        }

        connect(discovery, device)
    }

    private suspend fun connect(
        discovery: UsbCameraDiscovery,
        device: UsbDevice,
    ) {
        withContext(usbDispatcher) {
            try {
                val camera = discovery.open(device)
                opened = camera
                _state.value =
                    ConnectionState.Opened(
                        productName = camera.productName,
                        bulkInAddress = camera.endpoints.bulkIn.address,
                        bulkOutAddress = camera.endpoints.bulkOut.address,
                        interruptInAddress = camera.endpoints.interruptIn?.address ?: -1,
                        bulkInMaxPacketSize = camera.endpoints.bulkIn.maxPacketSize,
                    )
                CanonLog.i("Connected: %s", camera.endpoints)
                openPtpSession(camera.productName)
            } catch (e: UsbError) {
                CanonLog.e(e, "Connect failed")
                _state.value = ConnectionState.Error(e.message ?: "USB error", e)
                releaseQuietly()
            } catch (e: Exception) {
                CanonLog.e(e, "Unexpected error while connecting")
                _state.value = ConnectionState.Error(e.message ?: e.javaClass.simpleName, e)
                releaseQuietly()
            }
        }
    }

    // ------------------------------------------------------------------ ptp

    /**
     * Opens the PTP session and dumps the camera's capabilities.
     *
     * The dump is written on every connect rather than on demand. It is small, it is the
     * authoritative answer to every later "does this body support X?" question, and the
     * one time you want it is when something has just gone wrong - which is exactly when
     * nobody remembers to press a button.
     */
    private fun openPtpSession(productName: String?) {
        val transport = opened?.transport ?: return
        val ptp = PtpSession(transport)

        try {
            // U-06 / U-17: if the last session ended uncleanly the endpoints may still hold
            // a partial live-view frame, so the interface still has to be drained here.
            //
            // Drain *only*, deliberately. This used to call recoverFromStall, which clears
            // the endpoint halt as well — and clearing a halt that was never set is what
            // caused the `1140862976` misparse it was meant to cure. See
            // UsbTransport.settleFreshClaim for the toggle argument. A genuine stall is
            // still cleared, just from the retry path once a transfer has actually failed.
            transport.settleFreshClaim()

            // GetDeviceInfo works before a session is open, so we learn what the body
            // supports before committing to anything.
            val info = CameraSessionHandshake.readDeviceInfoWithRetries(ptp, transport)
            ptp.openSession(1)
            session = ptp

            _state.value =
                ConnectionState.SessionOpen(
                    productName = productName ?: info.model,
                    sessionId = ptp.sessionId,
                )

            CameraSessionHandshake.writeCapabilityDump(info, capabilityDumpDir)
            CameraSessionHandshake.warnAboutMissingCapabilities(info)
            startEosSession(info)
        } catch (e: PtpException) {
            CanonLog.e(e, "PTP session failed to open")
            _state.value = ConnectionState.Error(e.message ?: "PTP error", e)
            // Hand the interface back. connect()'s own catch cannot do it - this block
            // swallows the exception - so without this the claimed-but-unusable device
            // survives every retry and only a replug clears it.
            releaseQuietly()
        }
    }

    /**
     * Enters EOS remote mode and starts the event loop.
     *
     * Gated on the capability dump: if the body does not report the remote-mode opcodes,
     * attempting the handshake produces a confusing failure. Better to say plainly that
     * this body cannot do it and leave the PTP session usable for everything else.
     */
    private fun startEosSession(info: PtpDeviceInfo) {
        if (!info.supportsEosRemoteMode) {
            CanonLog.e("Skipping EOS handshake - this body does not report the remote-mode opcodes")
            return
        }

        val ptp = session ?: return
        val eos = EosSession(ptp, scope)

        try {
            eos.start()
            eosSession = eos

            val props = EosProperties(ptp)
            val capture = EosCapture(ptp, props)
            capture.configureForHostCapture() // P-05, must precede any release
            // C-17: the body's own self-timer would otherwise count down on every release.
            capture.useSingleShotDrive()
            eosCapture = capture

            val store = imageStore ?: ImageStore(java.io.File(System.getProperty("java.io.tmpdir") ?: "."))
            captureQueue = CaptureQueue(capture, eos, store, scope).also { it.start() }
            liveView = EosLiveView(ptp, props, scope)
            cameraSettings = EosCameraSettings(eos, props, scope).also { it.start() }
            // C-15: EXIF timestamps drift otherwise, and downstream ordering breaks.
            cameraSettings?.syncClock()

            _state.value = ConnectionState.Ready

            // Watch for the loop wedging so the UI reflects it rather than looking healthy
            // while capture silently stops working (C-01, O-06).
            scope.launch {
                eos.state.collect { eosState ->
                    if (eosState == EosSession.State.Wedged) {
                        _state.value = ConnectionState.Wedged("EOS event loop stopped responding")
                    }
                }
            }
        } catch (e: PtpException) {
            CanonLog.e(e, "EOS handshake failed - M4 capture cannot work until this passes")
            _state.value = ConnectionState.Error("EOS handshake failed: ${e.message}", e)
            // The booth cannot capture without remote mode, and leaving the PTP session
            // live here would keep `session != null`, so the reconnect guard above would
            // read this as a healthy link and skip the retry.
            releaseQuietly()
        }
    }

    // ------------------------------------------------------------- teardown

    /**
     * Called from the USB_DEVICE_DETACHED broadcast.
     *
     * Must never throw: it runs on a broadcast receiver during cable-pull, which is
     * exactly when things are in a bad state. Anything that escapes here becomes a crash
     * in front of the user.
     */
    fun onDeviceDetached(device: UsbDevice?) {
        CanonLog.w("USB_DEVICE_DETACHED: %s", device?.deviceName ?: "unknown")
        scope.launch {
            releaseQuietly()
            _state.value = ConnectionState.Detached
        }
    }

    fun disconnect() {
        scope.launch { disconnectAndAwait() }
    }

    /** Tears down USB/PTP synchronously — used before a reconnect retry. */
    suspend fun disconnectAndAwait() {
        withContext(usbDispatcher) {
            releaseQuietly()
            _state.value = ConnectionState.NoDevice
        }
    }

    /** Mirror-cycle settling time before live view is re-enabled after a capture. */
    private const val LIVE_VIEW_RESUME_DELAY_MS = 400L

    /** Settling time between stopping live view and firing the shutter. */
    private const val LIVE_VIEW_SETTLE_BEFORE_RELEASE_MS = 400L

    /**
     * Releases the interface and closes the connection, swallowing failures.
     *
     * Leaking either is what produces U-11: works for N reconnect cycles, then stops
     * because file descriptors have run out.
     */
    private fun releaseQuietly() {
        // Teardown order is deliberate and matters:
        //   EOS remote mode -> PTP session -> USB transport
        // Each step needs the one below it still working. Reversing this leaves the
        // camera in a state that needs a power cycle before it will connect again.
        // Live view first: leaving it on holds the mirror up, draining the battery and
        // heating the sensor (C-09).
        liveView?.let { runCatching { it.stop() } }
        liveView = null
        cameraSettings = null

        captureQueue = null
        // Leave the camera able to shoot to its own card standalone.
        eosCapture?.let { runCatching { it.restoreCardCapture() } }
        eosCapture = null

        eosSession?.let { eos ->
            runCatching { eos.stop() }
                .onFailure { CanonLog.w(it, "Error stopping EOS session") }
        }
        eosSession = null

        session?.let { ptp ->
            runCatching { ptp.closeSession() }
                .onFailure { CanonLog.w(it, "Error closing PTP session") }
        }
        session = null

        val camera = opened ?: return
        opened = null
        runCatching { camera.transport.close() }
            .onFailure { CanonLog.w(it, "Error closing transport") }
        CanonLog.i("Session released")
    }
}
