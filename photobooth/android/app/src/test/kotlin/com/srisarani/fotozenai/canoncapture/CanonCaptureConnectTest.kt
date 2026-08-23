package com.srisarani.fotozenai.canoncapture

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.state.ConnectionState
import org.junit.Test

class CanonCaptureConnectTest {

    @Test
    fun `ready states are connect outcomes and ready for capture`() {
        assertThat(CanonCaptureConnect.isReady(ConnectionState.Ready)).isTrue()
        assertThat(CanonCaptureConnect.isReady(ConnectionState.LiveView)).isTrue()
        assertThat(CanonCaptureConnect.isConnectOutcome(ConnectionState.Ready)).isTrue()
        assertThat(CanonCaptureConnect.isConnectOutcome(ConnectionState.NoDevice)).isTrue()
        assertThat(CanonCaptureConnect.isConnectOutcome(ConnectionState.Scanning)).isFalse()
    }

    @Test
    fun `stale ptp sessions are the half-open states`() {
        assertThat(CanonCaptureConnect.isStalePtpSession(ConnectionState.Opened(
            productName = "EOS",
            bulkInAddress = 1,
            bulkOutAddress = 2,
            interruptInAddress = -1,
            bulkInMaxPacketSize = 512,
        ))).isTrue()
        assertThat(CanonCaptureConnect.isStalePtpSession(ConnectionState.Ready)).isFalse()
        assertThat(CanonCaptureConnect.isStalePtpSession(ConnectionState.NoDevice)).isFalse()
    }

    @Test
    fun `typed errors map permission device and host failures`() {
        val denied = CanonCaptureConnect.errorResult(ConnectionState.PermissionDenied("cam"))
        assertThat(denied?.errorCode).isEqualTo(CaptureSessionContract.ERROR_PERMISSION_DENIED)

        val missing = CanonCaptureConnect.errorResult(ConnectionState.NoDevice)
        assertThat(missing?.errorCode).isEqualTo(CaptureSessionContract.ERROR_NO_DEVICE)

        val host = CanonCaptureConnect.errorResult(ConnectionState.NoUsbHostSupport)
        assertThat(host?.errorCode).isEqualTo(CaptureSessionContract.ERROR_CONNECT_FAILED)

        assertThat(CanonCaptureConnect.errorResult(ConnectionState.Scanning)).isNull()
    }

    @Test
    fun `describe uses the typed message when present`() {
        assertThat(CanonCaptureConnect.describe(ConnectionState.Error("boom"))).isEqualTo("boom")
        assertThat(CanonCaptureConnect.describe(ConnectionState.Wedged("stuck"))).isEqualTo("stuck")
        assertThat(CanonCaptureConnect.describe(null)).contains("Timed out")
        assertThat(CanonCaptureConnect.describe(ConnectionState.Ready)).isEqualTo("Ready")
    }
}
