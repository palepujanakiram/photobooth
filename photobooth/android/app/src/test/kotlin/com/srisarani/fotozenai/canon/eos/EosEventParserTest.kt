package com.srisarani.fotozenai.canon.eos

import com.google.common.truth.Truth.assertThat
import com.srisarani.fotozenai.canon.ptp.PtpWriter
import org.junit.Test

/**
 * The event parser runs inside the event loop. If it can throw, the loop can die, and a
 * dead event loop silently breaks capture (C-01) while looking like a bug in the capture
 * code. So these tests care as much about **not throwing on garbage** as about decoding
 * valid input.
 */
class EosEventParserTest {

    /** Builds one record in the documented `u32 size, u32 type, payload` layout. */
    private fun record(type: Int, payload: ByteArray = ByteArray(0)): ByteArray =
        PtpWriter()
            .u32((8 + payload.size).toLong())
            .u32(type.toLong())
            .bytes(payload)
            .toByteArray()

    private fun terminator(): ByteArray = PtpWriter().u32(0L).toByteArray()

    private fun objectAddedPayload(
        handle: Long = 0x00001234,
        storage: Long = 0x00010001,
        format: Int = 0x3801,
        size: Long = 7_340_032,
        name: String = "IMG_0042.JPG",
    ): ByteArray = PtpWriter()
        .u32(handle)
        .u32(storage)
        .u32(format.toLong())
        .u32(0L) // reserved
        .u32(size)
        .bytes(name.toByteArray(Charsets.US_ASCII))
        .u8(0)
        .toByteArray()

    // ================================================================ decoding

    @Test
    fun `decodes an object added event - M4's capture trigger`() {
        val bytes = record(EosEventCode.OBJECT_ADDED_EX, objectAddedPayload()) + terminator()

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(1)
        val added = events.first() as EosEvent.ObjectAdded
        assertThat(added.objectHandle).isEqualTo(0x1234L)
        assertThat(added.sizeBytes).isEqualTo(7_340_032L)
        assertThat(added.filename).isEqualTo("IMG_0042.JPG")
    }

    @Test
    fun `decodes several records in one response`() {
        val bytes = record(EosEventCode.OBJECT_ADDED_EX, objectAddedPayload()) +
            record(EosEventCode.PROP_VALUE_CHANGED, PtpWriter().u32(0xD103L).u32(400L).toByteArray()) +
            record(EosEventCode.AF_RESULT, PtpWriter().u32(1L).toByteArray()) +
            terminator()

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(3)
        assertThat(events[0]).isInstanceOf(EosEvent.ObjectAdded::class.java)
        assertThat((events[1] as EosEvent.PropertyChanged).propertyCode).isEqualTo(0xD103)
        assertThat((events[2] as EosEvent.AfResult).result).isEqualTo(1L)
    }

    @Test
    fun `decodes af result - needed to tell AF failure from a dead event loop`() {
        val bytes = record(EosEventCode.AF_RESULT, PtpWriter().u32(0L).toByteArray())

        val event = EosEventParser.parse(bytes).single() as EosEvent.AfResult

        assertThat(event.result).isEqualTo(0L)
    }

    @Test
    fun `decodes will soon shutdown`() {
        val bytes = record(EosEventCode.WILL_SOON_SHUTDOWN)

        assertThat(EosEventParser.parse(bytes).single()).isInstanceOf(EosEvent.WillSoonShutdown::class.java)
    }

    @Test
    fun `storage events collapse to a single type`() {
        val bytes = record(EosEventCode.STORE_ADDED) + record(EosEventCode.STORAGE_INFO_CHANGED)

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(2)
        assertThat(events.all { it is EosEvent.StorageChanged }).isTrue()
    }

    // ================================================================ robustness

    /**
     * The plan's M3 note, tested: log unknown event codes rather than throwing. An
     * unrecognised code must cost us a feature, never the session.
     */
    @Test
    fun `unknown event code is preserved with its raw payload, not dropped`() {
        val payload = byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte())
        val bytes = record(0xC999, payload) + terminator()

        val event = EosEventParser.parse(bytes).single() as EosEvent.Unknown

        assertThat(event.code).isEqualTo(0xC999)
        assertThat(event.payload).isEqualTo(payload)
        // Raw bytes must survive so the record can be decoded later from a committed log.
        assertThat(event.toString()).contains("DE AD BE EF")
    }

    @Test
    fun `an unknown record does not stop later records parsing`() {
        val bytes = record(0xC999, byteArrayOf(1, 2, 3, 4)) +
            record(EosEventCode.OBJECT_ADDED_EX, objectAddedPayload()) +
            terminator()

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(2)
        assertThat(events[1]).isInstanceOf(EosEvent.ObjectAdded::class.java)
    }

    /**
     * A truncated payload on a known event type would throw inside the decoder. It must be
     * caught and downgraded to Unknown, keeping the loop alive.
     */
    @Test
    fun `a truncated known event degrades to unknown instead of throwing`() {
        // ObjectAdded needs 20 bytes of fixed fields; give it 4.
        val bytes = record(EosEventCode.OBJECT_ADDED_EX, byteArrayOf(1, 2, 3, 4))

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(1)
        assertThat(events.single()).isInstanceOf(EosEvent.Unknown::class.java)
    }

    /**
     * Observed on a real 200D II: the body emits 8-byte records with type 0 as padding,
     * several per poll. Logging them as "unknown" buried the events that mattered.
     */
    @Test
    fun `type zero padding records are skipped silently`() {
        val bytes = record(0) +
            record(EosEventCode.AF_RESULT, PtpWriter().u32(1L).toByteArray()) +
            record(0) +
            terminator()

        val events = EosEventParser.parse(bytes)

        assertThat(events).hasSize(1)
        assertThat(events.single()).isInstanceOf(EosEvent.AfResult::class.java)
    }

    @Test
    fun `empty payload yields no events`() {
        assertThat(EosEventParser.parse(ByteArray(0))).isEmpty()
    }

    @Test
    fun `bare terminator yields no events`() {
        assertThat(EosEventParser.parse(terminator())).isEmpty()
    }

    @Test
    fun `implausible record size stops parsing without throwing`() {
        val bytes = PtpWriter().u32(0x7FFFFFFFL).u32(0xC181L).toByteArray()

        assertThat(EosEventParser.parse(bytes)).isEmpty() // no throw
    }

    @Test
    fun `record size smaller than its header stops parsing`() {
        val bytes = PtpWriter().u32(4L).u32(0xC181L).toByteArray()

        assertThat(EosEventParser.parse(bytes)).isEmpty()
    }

    @Test
    fun `record declaring more payload than remains is dropped, keeping earlier events`() {
        val good = record(EosEventCode.AF_RESULT, PtpWriter().u32(1L).toByteArray())
        val truncated = PtpWriter().u32(500L).u32(0xC181L).bytes(ByteArray(10)).toByteArray()

        val events = EosEventParser.parse(good + truncated)

        assertThat(events).hasSize(1)
        assertThat(events.single()).isInstanceOf(EosEvent.AfResult::class.java)
    }

    @Test
    fun `trailing garbage shorter than a header is ignored`() {
        val bytes = record(EosEventCode.AF_RESULT, PtpWriter().u32(1L).toByteArray()) +
            byteArrayOf(0x01, 0x02, 0x03)

        assertThat(EosEventParser.parse(bytes)).hasSize(1)
    }

    /**
     * The strongest guarantee this parser makes: whatever bytes arrive, it returns a list
     * rather than throwing. Random input is a fair proxy for a body doing something we did
     * not anticipate.
     */
    @Test
    fun `random bytes never throw`() {
        val random = java.util.Random(20260813)
        repeat(500) {
            val bytes = ByteArray(random.nextInt(200)).also { random.nextBytes(it) }
            EosEventParser.parse(bytes) // must not throw
        }
    }

    @Test
    fun `event code names are human readable in logs`() {
        assertThat(EosEventCode.name(EosEventCode.OBJECT_ADDED_EX)).isEqualTo("ObjectAddedEx")
        assertThat(EosEventCode.name(0xC999)).isEqualTo("EosEvent(0xC999)")
    }
}
