package com.srisarani.fotozenai.canon.state

/**
 * Link state machine. docs/PLAN.md section 5.
 *
 * The point of enumerating these is that "connected" hides at least six meaningfully
 * different states. A user staring at a green light while the camera silently refuses to
 * fire is the exact failure this model exists to prevent.
 *
 * M0 defines the contract; M1 drives it from real USB events; M3 adds [RemoteMode] onward.
 */
sealed interface ConnectionState {

    /** The device itself cannot host USB. Terminal - nothing about this app can work (U-07). */
    data object NoUsbHostSupport : ConnectionState

    /** Host capable, nothing plugged in. The normal idle state. */
    data object NoDevice : ConnectionState

    /** A matching device is present but we have not been granted access yet. */
    data class DeviceFound(
        val deviceName: String,
        val productName: String?,
        val vendorId: Int,
        val productId: Int,
        val permissionPending: Boolean,
    ) : ConnectionState

    /** The user declined the USB permission dialog, or it was revoked (U-03). */
    data class PermissionDenied(val deviceName: String) : ConnectionState

    /** Interface claimed, endpoints resolved. USB is usable; PTP has not started. */
    data class Opened(
        val productName: String?,
        val bulkInAddress: Int,
        val bulkOutAddress: Int,
        val interruptInAddress: Int,
        val bulkInMaxPacketSize: Int,
    ) : ConnectionState

    /** PTP OpenSession succeeded. Generic PTP works; Canon remote mode has not started. */
    data class SessionOpen(val productName: String?, val sessionId: Int) : ConnectionState

    /** Canon EOS handshake complete and the event loop is draining (M3). */
    data class RemoteMode(val productName: String?) : ConnectionState

    /** Idle and able to accept a capture. */
    data object Ready : ConnectionState

    /** A capture is in flight. */
    data object Busy : ConnectionState

    /** Pulling an image off the camera. */
    data class Downloading(val bytesRead: Long, val bytesTotal: Long) : ConnectionState

    /** Live view is streaming. */
    data object LiveView : ConnectionState

    /** Watchdog fired - no events for N seconds. Session presumed wedged (O-06). */
    data class Wedged(val reason: String) : ConnectionState

    /** Automatic re-initialisation in progress. */
    data class Recovering(val attempt: Int) : ConnectionState

    /** Cable pulled or device removed. */
    data object Detached : ConnectionState

    /** Something we could not classify. Always carries the detail rather than swallowing it. */
    data class Error(val message: String, val cause: Throwable? = null) : ConnectionState
}

/** Short label for the status chip. */
val ConnectionState.label: String
    get() = when (this) {
        ConnectionState.NoUsbHostSupport -> "USB host unsupported"
        ConnectionState.NoDevice -> "No camera"
        is ConnectionState.DeviceFound -> if (permissionPending) "Awaiting permission" else "Camera found"
        is ConnectionState.PermissionDenied -> "Permission denied"
        is ConnectionState.Opened -> "USB open"
        is ConnectionState.SessionOpen -> "PTP session open"
        is ConnectionState.RemoteMode -> "Remote mode"
        ConnectionState.Ready -> "Ready"
        ConnectionState.Busy -> "Capturing"
        is ConnectionState.Downloading -> "Downloading"
        ConnectionState.LiveView -> "Live view"
        is ConnectionState.Wedged -> "Wedged"
        is ConnectionState.Recovering -> "Recovering"
        ConnectionState.Detached -> "Detached"
        is ConnectionState.Error -> "Error"
    }

/** True when the pipeline is healthy enough to attempt a capture. */
val ConnectionState.isOperational: Boolean
    get() = this is ConnectionState.Ready ||
        this is ConnectionState.Busy ||
        this is ConnectionState.Downloading ||
        this is ConnectionState.LiveView ||
        this is ConnectionState.RemoteMode

/** True when the state warrants a red indicator rather than amber or green. */
val ConnectionState.isFault: Boolean
    get() = this is ConnectionState.Error ||
        this is ConnectionState.Wedged ||
        this is ConnectionState.PermissionDenied ||
        this is ConnectionState.NoUsbHostSupport
