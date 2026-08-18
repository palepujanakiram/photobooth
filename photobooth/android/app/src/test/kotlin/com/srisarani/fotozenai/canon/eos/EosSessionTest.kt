package com.srisarani.fotozenai.canon.eos

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpContainer
import com.srisarani.fotozenai.canon.ptp.PtpContainerType
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpResponse
import com.srisarani.fotozenai.canon.ptp.PtpSession
import com.srisarani.fotozenai.canon.ptp.PtpWriter
import com.srisarani.fotozenai.canon.usb.FakeUsbBulkChannel
import com.srisarani.fotozenai.canon.usb.UsbTransport
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertThrows
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class EosSessionTest {

    private val packetSize = 512

    private class Rig {
        val channel = FakeUsbBulkChannel(512)
        val transport = UsbTransport(channel, UsbTransport.Config(readTimeoutMs = 50, zlpTimeoutMs = 2))
        val ptp = PtpSession(transport)

        fun ok(transactionId: Long) {
            channel.enqueueTransfer(
                PtpContainer(PtpContainerType.RESPONSE, PtpResponse.OK, transactionId).toByteArray(),
            )
        }

        fun fail(transactionId: Long, code: Int) {
            channel.enqueueTransfer(
                PtpContainer(PtpContainerType.RESPONSE, code, transactionId).toByteArray(),
            )
        }

        /** A GetEvent data phase followed by its OK response. */
        fun eventResponse(transactionId: Long, eventBytes: ByteArray) {
            channel.enqueueTransfer(
                PtpContainer.data(CanonEosOperation.GET_EVENT, transactionId, eventBytes).toByteArray(),
            )
            ok(transactionId)
        }

        fun sentOpcodes(): List<Int> =
            channel.writes.map { PtpContainer.parse(it) }
                .filter { it.type == PtpContainerType.COMMAND }
                .map { it.code }
    }

    private fun eventRecord(type: Int, payload: ByteArray = ByteArray(0)): ByteArray =
        PtpWriter().u32((8 + payload.size).toLong()).u32(type.toLong()).bytes(payload).toByteArray()

    // ================================================================ handshake

    @Test
    fun `start performs SetRemoteMode then SetEventMode in order`() = runTest {
        val rig = Rig()
        rig.ok(0) // SetRemoteMode
        rig.ok(1) // SetEventMode

        val session = EosSession(rig.ptp, backgroundScope)
        session.start()

        assertThat(rig.sentOpcodes().take(2))
            .containsExactly(CanonEosOperation.SET_REMOTE_MODE, CanonEosOperation.SET_EVENT_MODE)
            .inOrder()
        assertThat(session.state.value).isEqualTo(EosSession.State.Running)

        session.stop()
    }

    /**
     * If the handshake fails there is no point starting the loop. Failing loudly here is
     * far kinder than a silent hang at M4 that looks like a capture bug (C-01).
     */
    @Test
    fun `handshake failure throws and leaves the session stopped`() = runTest {
        val rig = Rig()
        rig.fail(0, PtpResponse.OPERATION_NOT_SUPPORTED)

        val session = EosSession(rig.ptp, backgroundScope)

        assertThrows(PtpException.OperationFailed::class.java) { session.start() }
        assertThat(session.state.value).isEqualTo(EosSession.State.Stopped)
    }

    @Test
    fun `start is idempotent`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)

        val session = EosSession(rig.ptp, backgroundScope)
        session.start()
        session.start() // must not re-handshake

        assertThat(rig.sentOpcodes().count { it == CanonEosOperation.SET_REMOTE_MODE }).isEqualTo(1)
        session.stop()
    }

    // ================================================================ event loop

    @Test
    fun `event loop polls GetEvent and emits decoded events`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)
        rig.eventResponse(2, eventRecord(EosEventCode.AF_RESULT, PtpWriter().u32(1L).toByteArray()))

        val received = mutableListOf<EosEvent>()
        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 100, keepAliveIntervalMs = 100_000),
        )
        val collector = backgroundScope.launch { session.events.collect { received += it } }

        session.start()
        advanceTimeBy(150)

        assertThat(session.pollCount).isAtLeast(1L)
        assertThat(received.filterIsInstance<EosEvent.AfResult>()).isNotEmpty()

        session.stop()
        collector.cancel()
    }

    /**
     * **The most important behaviour in this class.** The loop must survive failures - a
     * dead event loop does not announce itself, it just makes capture stop working (C-01).
     */
    @Test
    fun `event loop survives poll failures and keeps polling`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)
        // Nothing queued for the polls: every one times out.

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 10, keepAliveIntervalMs = 100_000, maxConsecutiveFailures = 100),
        )
        session.start()
        advanceTimeBy(200)

        assertThat(session.consecutiveFailures).isGreaterThan(1)
        assertThat(session.state.value).isEqualTo(EosSession.State.Running) // still alive
        assertThat(session.pollCount).isGreaterThan(1L)

        session.stop()
    }

    /**
     * Surviving forever would be wrong too. After enough consecutive failures the session
     * is declared wedged so the M11 watchdog can re-initialise it (O-06).
     */
    @Test
    fun `event loop declares itself wedged after repeated failures`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 5, keepAliveIntervalMs = 100_000, maxConsecutiveFailures = 3),
        )
        session.start()
        advanceTimeBy(200)

        assertThat(session.state.value).isEqualTo(EosSession.State.Wedged)
    }

    @Test
    fun `a successful poll resets the failure counter`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 10, keepAliveIntervalMs = 100_000, maxConsecutiveFailures = 100),
        )
        session.start()
        advanceTimeBy(50) // accumulate failures
        val failuresBefore = session.consecutiveFailures
        assertThat(failuresBefore).isGreaterThan(0)

        // Now let a poll succeed.
        rig.eventResponse(session.pollCount + 2, ByteArray(0))
        advanceTimeBy(50)

        session.stop()
    }

    @Test
    fun `malformed event payload does not kill the loop`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)
        // Garbage where an event array should be.
        rig.eventResponse(2, byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()))

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 10, keepAliveIntervalMs = 100_000, maxConsecutiveFailures = 100),
        )
        session.start()
        advanceTimeBy(100)

        assertThat(session.state.value).isEqualTo(EosSession.State.Running)
        session.stop()
    }

    // ================================================================ keepalive

    @Test
    fun `keepalive is sent on its interval`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)
        repeat(20) { rig.ok((it + 2).toLong()) }

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 100_000, keepAliveIntervalMs = 50),
        )
        session.start()
        advanceTimeBy(120)

        assertThat(rig.sentOpcodes()).contains(CanonEosOperation.KEEP_DEVICE_ON)
        session.stop()
    }

    /**
     * A body that does not implement KeepDeviceOn should not produce a failure log every
     * ten seconds forever.
     */
    @Test
    fun `keepalive stops permanently if the body does not support it`() = runTest {
        val rig = Rig()
        rig.ok(0) // SetRemoteMode
        rig.ok(1) // SetEventMode
        // The event loop polls ONCE IMMEDIATELY on start rather than waiting out the
        // first interval - deliberate, so events are not delayed by up to pollIntervalMs.
        // That poll consumes transaction 2, so the keepalive is transaction 3.
        rig.eventResponse(2, ByteArray(0))
        rig.fail(3, PtpResponse.OPERATION_NOT_SUPPORTED)

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 100_000, keepAliveIntervalMs = 10),
        )
        session.start()
        advanceTimeBy(200)

        val keepAliveCount = rig.sentOpcodes().count { it == CanonEosOperation.KEEP_DEVICE_ON }
        assertThat(keepAliveCount).isEqualTo(1) // tried once, gave up permanently

        session.stop()
    }

    // ================================================================ shutdown

    /**
     * Order matters: stop polling BEFORE releasing remote mode. Releasing while the loop
     * still runs races a GetEvent against the mode change and can leave the camera in a
     * state that needs a power cycle.
     */
    @Test
    fun `stop releases event mode and remote mode`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)
        repeat(10) { rig.ok((it + 2).toLong()) }

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 100_000, keepAliveIntervalMs = 100_000),
        )
        session.start()
        session.stop()

        val opcodes = rig.sentOpcodes()
        assertThat(opcodes).contains(CanonEosOperation.SET_EVENT_MODE)
        assertThat(opcodes).contains(CanonEosOperation.SET_REMOTE_MODE)
        assertThat(session.state.value).isEqualTo(EosSession.State.Stopped)
    }

    @Test
    fun `stop never throws when the camera has already gone`() = runTest {
        val rig = Rig()
        rig.ok(0); rig.ok(1)

        val session = EosSession(
            rig.ptp,
            backgroundScope,
            EosSession.Config(pollIntervalMs = 100_000, keepAliveIntervalMs = 100_000),
        )
        session.start()
        rig.channel.close() // cable pulled

        session.stop() // must not throw

        assertThat(session.state.value).isEqualTo(EosSession.State.Stopped)
    }

    @Test
    fun `stop on a stopped session is a no-op`() = runTest {
        val rig = Rig()
        val session = EosSession(rig.ptp, backgroundScope)

        session.stop()

        assertThat(rig.channel.writes).isEmpty()
    }

    @Test
    fun `millis since last event reports -1 before any event`() = runTest {
        val rig = Rig()
        val session = EosSession(rig.ptp, backgroundScope)

        assertThat(session.millisSinceLastEvent()).isEqualTo(-1L)
    }
}
