package com.srisarani.fotozenai.canoncapture

import com.srisarani.fotozenai.canon.state.ConnectionState
import com.srisarani.fotozenai.canon.state.isReadyForCapture

/**
 * Pure connect-outcome helpers for [CanonCaptureActivity].
 *
 * Kept out of the Activity so the USB wait loop stays under Qlty's complexity budget.
 */
internal object CanonCaptureConnect {
    fun isConnectOutcome(state: ConnectionState): Boolean =
        when (state) {
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

    fun isReady(state: ConnectionState): Boolean = state.isReadyForCapture

    fun isStalePtpSession(state: ConnectionState): Boolean =
        when (state) {
            is ConnectionState.Error,
            is ConnectionState.Wedged,
            is ConnectionState.SessionOpen,
            is ConnectionState.Opened,
            -> true

            else -> false
        }

    fun errorResult(state: ConnectionState): CaptureSessionContract.Result? =
        when (state) {
            is ConnectionState.PermissionDenied -> {
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_PERMISSION_DENIED,
                    "USB permission was refused for the camera",
                )
            }

            is ConnectionState.NoDevice -> {
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_NO_DEVICE,
                    "No camera found. Check the cable and that the camera is switched on.",
                )
            }

            is ConnectionState.NoUsbHostSupport -> {
                CaptureSessionContract.Result.error(
                    CaptureSessionContract.ERROR_CONNECT_FAILED,
                    "This device cannot host USB",
                )
            }

            else -> {
                null
            }
        }

    fun describe(state: ConnectionState?): String =
        when (state) {
            is ConnectionState.Error -> state.message
            is ConnectionState.Wedged -> state.reason
            null -> "Timed out waiting for the camera"
            else -> state::class.simpleName ?: "Unknown camera state"
        }
}
