package com.srisarani.fotozenai.canoncapture

import android.content.Context
import com.srisarani.fotozenai.canon.CanonLog
import com.srisarani.fotozenai.canon.session.CameraSessionManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Connects the capture Activity to a ready PTP session.
 *
 * Extracted so the wait/`drop(1)` loop does not inflate [CanonCaptureActivity] past Qlty's
 * file-complexity budget. Timing and retry rules match the previous inline method.
 */
internal class CanonCaptureConnector(
    private val appContext: Context,
    private val host: Host,
) {

    interface Host {
        val isFinished: Boolean
        fun finishWith(result: CaptureSessionContract.Result)
    }

    /** Connects if needed; finishes the Activity with a typed error if it cannot. */
    suspend fun ensureConnected(): Boolean {
        if (CanonCaptureConnect.isReady(CameraSessionManager.state.value)) return true

        if (CanonCaptureConnect.isStalePtpSession(CameraSessionManager.state.value)) {
            CameraSessionManager.disconnectAndAwait()
        }

        repeat(2) { attempt ->
            CameraSessionManager.scanAndConnect(appContext)
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
                host.finishWith(error)
            } else if (attempt == 0) {
                CanonLog.w("Connect attempt ${attempt + 1} stalled at $state — retrying")
                CameraSessionManager.disconnectAndAwait()
                delay(RETRY_PAUSE_MS)
            } else {
                host.finishWith(
                    CaptureSessionContract.Result.error(
                        CaptureSessionContract.ERROR_CONNECT_FAILED,
                        CanonCaptureConnect.describe(state),
                    ),
                )
            }
            if (host.isFinished) return false
        }
        return false
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 30_000L
        const val RETRY_PAUSE_MS = 1_500L
    }
}
