package com.srisarani.fotozenai.canon.state

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * The state model's whole purpose is that the UI can never show a misleading green light
 * (plan section 5). These tests pin the classification, because a mis-sorted state is
 * exactly the bug the model exists to prevent.
 */
class ConnectionStateTest {

    @Test
    fun `faults are classified as faults`() {
        val faults = listOf(
            ConnectionState.NoUsbHostSupport,
            ConnectionState.PermissionDenied("dev"),
            ConnectionState.Wedged("no events for 10s"),
            ConnectionState.Error("boom"),
        )
        faults.forEach { assertThat(it.isFault).isTrue() }
        faults.forEach { assertThat(it.isOperational).isFalse() }
    }

    @Test
    fun `transitional states are neither operational nor faults`() {
        val transitional = listOf(
            ConnectionState.NoDevice,
            ConnectionState.DeviceFound("dev", "EOS 200D II", 0x04A9, 0x32C5, permissionPending = true),
            ConnectionState.Detached,
            ConnectionState.Recovering(attempt = 2),
        )
        transitional.forEach {
            assertThat(it.isFault).isFalse()
            assertThat(it.isOperational).isFalse()
        }
    }

    @Test
    fun `operational states are operational`() {
        val operational = listOf(
            ConnectionState.RemoteMode("EOS 200D II"),
            ConnectionState.Ready,
            ConnectionState.Busy,
            ConnectionState.Downloading(bytesRead = 1024, bytesTotal = 7_000_000),
            ConnectionState.LiveView,
        )
        operational.forEach {
            assertThat(it.isOperational).isTrue()
            assertThat(it.isFault).isFalse()
        }
    }

    @Test
    fun `usb open is not yet operational`() {
        // Interface claimed is NOT the same as able to shoot. Conflating the two is
        // precisely the "green light while the camera refuses to fire" failure.
        val opened = ConnectionState.Opened("EOS 200D II", 0x81, 0x02, 0x83, 512)
        assertThat(opened.isOperational).isFalse()
        assertThat(opened.isFault).isFalse()
    }

    @Test
    fun `every state has a non-empty label`() {
        val all = listOf(
            ConnectionState.NoUsbHostSupport,
            ConnectionState.NoDevice,
            ConnectionState.DeviceFound("d", null, 0, 0, false),
            ConnectionState.PermissionDenied("d"),
            ConnectionState.Opened(null, 0, 0, 0, 512),
            ConnectionState.SessionOpen(null, 1),
            ConnectionState.RemoteMode(null),
            ConnectionState.Ready,
            ConnectionState.Busy,
            ConnectionState.Downloading(0, 0),
            ConnectionState.LiveView,
            ConnectionState.Wedged("r"),
            ConnectionState.Recovering(1),
            ConnectionState.Detached,
            ConnectionState.Error("m"),
        )
        all.forEach { assertThat(it.label).isNotEmpty() }
    }

    @Test
    fun `isReadyForCapture covers ready remote and live view only`() {
        assertThat(ConnectionState.Ready.isReadyForCapture).isTrue()
        assertThat(ConnectionState.RemoteMode(null).isReadyForCapture).isTrue()
        assertThat(ConnectionState.LiveView.isReadyForCapture).isTrue()
        assertThat(ConnectionState.SessionOpen(null, 1).isReadyForCapture).isFalse()
        assertThat(ConnectionState.Opened(null, 0, 0, 0, 512).isReadyForCapture).isFalse()
    }
}
