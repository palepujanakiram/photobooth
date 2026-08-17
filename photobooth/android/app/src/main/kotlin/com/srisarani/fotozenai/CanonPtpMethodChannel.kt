package com.srisarani.fotozenai

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.capture.CaptureStorage
import com.srisarani.fotozenai.canon.capture.ImageStore
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import com.srisarani.fotozenai.canon.state.ConnectionState
import com.srisarani.fotozenai.canon.state.isFault
import com.srisarani.fotozenai.canon.state.isOperational
import com.srisarani.fotozenai.canon.state.label
import com.srisarani.fotozenai.canon.usb.UsbCameraDiscovery
import com.srisarani.fotozenai.canoncapture.CanonCaptureActivity
import com.srisarani.fotozenai.canoncapture.CaptureSessionContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Flutter bridge to the direct-PTP Canon camera (`docs/direct-ptp-native-camera-plan.md`, P2).
 *
 * Connection lifecycle only. There is deliberately no capture or live view here: those
 * belong to the native capture Activity at P3/P4, and pushing image bytes across a method
 * channel is the thing the plan exists to avoid.
 *
 * Follows the same shape as [DnpUsbMethodChannel] / [ReceiptUsbMethodChannel] — an object
 * with `register` / `onResume` / `onDestroy`, wired from [MainActivity].
 */
object CanonPtpMethodChannel {
    const val METHOD_CHANNEL = "com.srisarani.fotozenai/canon_ptp"
    const val STATUS_CHANNEL = "com.srisarani.fotozenai/canon_ptp_status"

    /**
     * Budget for connect: USB open, PTP `OpenSession`, capability dump, EOS handshake.
     *
     * Generous because the camera can answer `DeviceBusy` for seconds while it wakes
     * (`P-18`/`P-21`), and the retry budgets underneath this are themselves ~10s. Timing out
     * does not fail the call — it returns whatever state the session actually reached, so
     * Dart can tell "still negotiating" from "refused".
     */
    private const val CONNECT_TIMEOUT_MS = 30_000L

    /** Request code for the native capture screen. */
    private const val CAPTURE_REQUEST_CODE = 0x0CA9

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private lateinit var appContext: Context

    /**
     * The hosting Activity, needed to start the capture screen for a result.
     *
     * Held only between `register` and `onDestroy`, and cleared there — [appContext] is used
     * for everything that outlives the Activity so this reference stays short-lived.
     */
    private var activity: Activity? = null

    /** The Dart call awaiting a capture session, if one is open. */
    private var pendingCaptureResult: MethodChannel.Result? = null

    private var statusSink: EventChannel.EventSink? = null
    private var detachReceiverRegistered = false

    /**
     * The camera we currently hold, tracked from the state stream.
     *
     * Needed because `CameraSessionManager.onDeviceDetached` tears the session down
     * unconditionally — correct in the camera-only POC, wrong here. This app can have the
     * DNP printer, the receipt printer and a Selphy on the bus at the same time, and
     * unplugging any of them would otherwise kill a live camera session.
     */
    @Volatile
    private var connectedDeviceName: String? = null

    /**
     * Mirrors USB detach into the session manager, for our camera only.
     *
     * Without this a pulled cable leaves the manager believing it still owns a live
     * endpoint, and the next transaction blocks until its timeout rather than failing fast.
     *
     * Matching on device name rather than "does it look like a camera" is deliberate: the
     * Canon Selphy is **the same vendor id (1193)** as the EOS body, so an interface-shape
     * test cannot reliably tell a detaching printer from a detaching camera.
     */
    private val usbDetachReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != UsbManager.ACTION_USB_DEVICE_DETACHED) return
            val held = connectedDeviceName ?: return
            val device = usbDeviceExtra(intent)
            if (device != null && device.deviceName != held) {
                CanonLog.d("Ignoring detach of %s; camera is %s", device.deviceName, held)
                return
            }
            CanonLog.i("Camera detached: %s", held)
            CameraSessionManager.onDeviceDetached(device)
        }
    }

    fun register(flutterEngine: FlutterEngine, context: Context) {
        activity = context as? Activity
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext

        // The manager is a singleton with no Context of its own, so it is handed the two
        // directories it needs rather than reaching for them.
        val root = CaptureStorage.resolveRoot(appContext)
        CameraSessionManager.imageStore = ImageStore(root)
        CameraSessionManager.capabilityDumpDir = appContext.filesDir
        CanonLog.i("Canon capture root: %s (public=%s)", root, CaptureStorage.isPublic(root))

        // Dump the bus once at startup. This is the first thing anyone looks at when the
        // camera "isn't detected", and it distinguishes the three cases that otherwise look
        // identical: nothing plugged in, plugged in but in the wrong USB mode (no
        // still-image interface), and plugged in but behind a hub that did not enumerate.
        runCatching { UsbCameraDiscovery(appContext).logAttachedDevices() }

        EventChannel(messenger, STATUS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statusSink = events
                    // Replay the current state: a listener attaching after connect would
                    // otherwise see nothing until the next transition, which on a healthy
                    // idle camera may never come.
                    events?.success(stateMap(CameraSessionManager.state.value))
                }

                override fun onCancel(arguments: Any?) {
                    statusSink = null
                }
            },
        )

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(::onMethodCall)

        scope.launch {
            CameraSessionManager.state.collect { state ->
                trackConnectedDevice(state)
                statusSink?.success(stateMap(state))
            }
        }
    }

    private fun trackConnectedDevice(state: ConnectionState) {
        when (state) {
            is ConnectionState.DeviceFound -> connectedDeviceName = state.deviceName
            is ConnectionState.Detached,
            is ConnectionState.NoDevice,
            is ConnectionState.NoUsbHostSupport,
            -> connectedDeviceName = null

            else -> Unit
        }
    }

    fun onResume(context: Context) {
        if (detachReceiverRegistered) return
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbDetachReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(usbDetachReceiver, filter)
        }
        detachReceiverRegistered = true
    }

    /**
     * Releases the camera when the app leaves the foreground.
     *
     * An open PTP session that dies with the process leaves the body mid-transaction: the
     * next connect reads the tail of the old transfer as a container header — *"Container
     * truncated: declared 1140862976"* — and clearing the stall does not recover it. The
     * camera then needs a physical power cycle, which on a booth is a site visit.
     *
     * Releasing on the way out makes the common exits clean: home button, task switch, a
     * kill while backgrounded. It cannot help a crash or a power cut, which is why the
     * stall/drain recovery on connect still exists.
     *
     * Skipped while a capture session is running — the native screen sits on top of
     * MainActivity, which stops it, and disconnecting there would cut the camera out from
     * under the shot in progress.
     */
    fun onStop() {
        if (pendingCaptureResult != null) {
            CanonLog.d("Capture in progress; keeping the camera session open")
            return
        }
        if (CameraSessionManager.state.value is ConnectionState.NoDevice) return
        CanonLog.i("App backgrounded — releasing the camera session cleanly")
        CameraSessionManager.disconnect()
    }

    fun onDestroy() {
        if (detachReceiverRegistered) {
            runCatching { appContext.unregisterReceiver(usbDetachReceiver) }
            detachReceiverRegistered = false
        }
        // A Dart call still awaiting a capture session must be answered, or the capture
        // flow waits on a Future that can never complete.
        pendingCaptureResult?.success(
            CaptureSessionContract.Result.cancelled("App shut down during capture").toMap(),
        )
        pendingCaptureResult = null
        activity = null
        statusSink = null
        CameraSessionManager.disconnect()
        scope.cancel()
    }

    // ------------------------------------------------------------------ methods

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Dart's AppLogger writes through dart:developer, which goes to the VM service and
        // never reaches logcat — so on a device the only evidence of what Dart asked for is
        // this line. Cheap: these are lifecycle calls, not a per-frame path.
        CanonLog.i("Channel call: %s", call.method)
        when (call.method) {
            "hasUsbHost" -> result.success(UsbCameraDiscovery(appContext).isUsbHostSupported)
            "probeDevice" -> result.success(probeDevice())
            "connect" -> connect(result)
            "status" -> result.success(stateMap(CameraSessionManager.state.value))
            "runCaptureSession" -> runCaptureSession(call, result)
            "disconnect" -> {
                CameraSessionManager.disconnect()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Opens the native capture screen and resolves with what it captured.
     *
     * The Activity owns live view, the shutter and the download; only file paths come back.
     * Dart is suspended on this call for the whole session, which is exactly the semantics
     * the capture flow wants — one await, one set of photos.
     */
    private fun runCaptureSession(call: MethodCall, result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.success(
                CaptureSessionContract.Result
                    .error(
                        CaptureSessionContract.ERROR_CONNECT_FAILED,
                        "No activity available to host the capture screen",
                    )
                    .toMap(),
            )
            return
        }
        if (pendingCaptureResult != null) {
            // Two capture screens would fight over one USB endpoint, and PTP is strictly
            // serialised — so refuse rather than queue.
            result.success(
                CaptureSessionContract.Result
                    .error(
                        CaptureSessionContract.ERROR_CAMERA_BUSY,
                        "A capture session is already running",
                    )
                    .toMap(),
            )
            return
        }

        val request = CaptureSessionContract.Request.fromMap(call.arguments as? Map<*, *>)
        pendingCaptureResult = result
        val intent = Intent(host, CanonCaptureActivity::class.java)
            .putExtra(CaptureSessionContract.EXTRA_REQUEST, request.toJson())
        host.startActivityForResult(intent, CAPTURE_REQUEST_CODE)
        host.overridePendingTransition(0, 0)
    }

    /**
     * Forwarded from `MainActivity.onActivityResult`.
     *
     * Returns true when it handled the code, so the host can fall through to anything else
     * that also uses `startActivityForResult`.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CAPTURE_REQUEST_CODE) return false
        val pending = pendingCaptureResult ?: return true
        pendingCaptureResult = null

        val captureResult = if (resultCode == Activity.RESULT_OK) {
            CaptureSessionContract.Result.fromIntent(data)
        } else {
            // A killed or dismissed Activity is a cancellation, not an error: nothing is
            // broken and the booth should simply return to where the guest was.
            CaptureSessionContract.Result.cancelled("Capture screen closed")
        }
        CanonLog.i(
            "Capture session result: %s (%d shots)",
            captureResult.status,
            captureResult.shots.size,
        )
        pending.success(captureResult.toMap())
        return true
    }

    /**
     * Reports what is on the bus without opening it.
     *
     * Separate from [connect] so Dart can tell "no camera plugged in" from "camera present
     * but permission refused" — one is an operator walking over with a cable, the other is
     * a dialog someone dismissed, and a booth should not present them identically.
     */
    private fun probeDevice(): Map<String, Any?>? {
        val discovery = UsbCameraDiscovery(appContext)
        if (!discovery.isUsbHostSupported) return null
        val device = discovery.findCameras().firstOrNull() ?: return null
        return mapOf(
            "deviceName" to device.deviceName,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "manufacturer" to device.manufacturerName,
            "product" to device.productName,
            "hasPermission" to discovery.hasPermission(device),
        )
    }

    private fun connect(result: MethodChannel.Result) {
        scope.launch {
            // Subscribe BEFORE kicking off the scan, and start UNDISPATCHED so the collector
            // is registered before scanAndConnect can emit. drop(1) skips the current value,
            // which is usually a terminal state left over from the previous attempt and would
            // otherwise resolve this call instantly with a stale answer.
            val terminal = async(start = CoroutineStart.UNDISPATCHED) {
                CameraSessionManager.state.drop(1).first(::isConnectOutcome)
            }

            CameraSessionManager.scanAndConnect(appContext)

            val reached = withTimeoutOrNull(CONNECT_TIMEOUT_MS) { terminal.await() }
            terminal.cancel()

            val state = reached ?: CameraSessionManager.state.value
            result.success(
                stateMap(state) + mapOf("timedOut" to (reached == null)),
            )
        }
    }

    /**
     * States that end a connect attempt.
     *
     * [ConnectionState.SessionOpen] is deliberately absent: on an EOS body it is a waypoint
     * on the way to [ConnectionState.Ready], and treating it as an outcome would report
     * success before the remote-mode handshake that capture depends on.
     */
    private fun isConnectOutcome(state: ConnectionState): Boolean = when (state) {
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

    private fun stateMap(state: ConnectionState): Map<String, Any?> {
        val base = mutableMapOf<String, Any?>(
            "state" to state::class.simpleName,
            "label" to state.label,
            "isOperational" to state.isOperational,
            "isFault" to state.isFault,
        )
        when (state) {
            is ConnectionState.DeviceFound -> {
                base["productName"] = state.productName
                base["vendorId"] = state.vendorId
                base["productId"] = state.productId
                base["permissionPending"] = state.permissionPending
            }

            is ConnectionState.Opened -> base["productName"] = state.productName
            is ConnectionState.SessionOpen -> base["productName"] = state.productName
            is ConnectionState.RemoteMode -> base["productName"] = state.productName
            is ConnectionState.PermissionDenied -> base["deviceName"] = state.deviceName
            is ConnectionState.Wedged -> base["message"] = state.reason
            is ConnectionState.Error -> base["message"] = state.message
            else -> Unit
        }
        return base
    }

    @Suppress("DEPRECATION")
    private fun usbDeviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
}
