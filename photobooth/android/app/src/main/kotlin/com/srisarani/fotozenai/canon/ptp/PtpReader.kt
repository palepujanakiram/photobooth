package com.srisarani.fotozenai.canon.ptp

/**
 * Little-endian cursor over a PTP payload.
 *
 * PTP is little-endian throughout, with no alignment padding: fields are packed back to
 * back. A parser that gets one field width wrong does not fail - it silently reads every
 * subsequent field from the wrong offset and produces plausible-looking garbage. Hence a
 * single shared cursor with strict bounds checks rather than ad-hoc offset arithmetic
 * scattered through each dataset parser.
 */
class PtpReader(private val data: ByteArray, startOffset: Int = 0) {

    var position: Int = startOffset
        private set

    val remaining: Int get() = data.size - position

    fun hasRemaining(): Boolean = remaining > 0

    private fun require(bytes: Int) {
        if (remaining < bytes) {
            throw PtpException.Malformed(
                "Truncated payload: need $bytes bytes at offset $position, only $remaining remain " +
                    "(total ${data.size})",
            )
        }
    }

    fun u8(): Int {
        require(1)
        return data[position++].toInt() and 0xFF
    }

    fun i8(): Int {
        require(1)
        return data[position++].toInt()
    }

    fun u16(): Int {
        require(2)
        val v = (data[position].toInt() and 0xFF) or
            ((data[position + 1].toInt() and 0xFF) shl 8)
        position += 2
        return v
    }

    fun i16(): Int = u16().toShort().toInt()

    /** Returns a Long so the full unsigned 32-bit range is representable. */
    fun u32(): Long {
        require(4)
        val v = (data[position].toLong() and 0xFF) or
            ((data[position + 1].toLong() and 0xFF) shl 8) or
            ((data[position + 2].toLong() and 0xFF) shl 16) or
            ((data[position + 3].toLong() and 0xFF) shl 24)
        position += 4
        return v
    }

    fun i32(): Int = u32().toInt()

    fun u64(): Long {
        require(8)
        var v = 0L
        for (i in 0 until 8) {
            v = v or ((data[position + i].toLong() and 0xFF) shl (8 * i))
        }
        position += 8
        return v
    }

    /**
     * Reads a PTP string.
     *
     * ## P-03 - the classic first bug
     *
     * The format is:
     *
     * ```
     * u8    numChars   <- CHARACTERS, INCLUDING the null terminator. NOT bytes.
     * u16[] chars      <- numChars UTF-16LE code units, the last being 0x0000
     * ```
     *
     * So a string occupies `1 + numChars * 2` bytes on the wire, and carries
     * `numChars - 1` actual characters.
     *
     * The bug everyone writes first is treating `numChars` as a byte count. It does not
     * throw and it does not look obviously wrong - the string itself often still renders
     * (you get half of it), but the cursor is left mid-string, so **every field parsed
     * after it is garbage**. In `GetDeviceInfo` that means the manufacturer string looks
     * odd and the model, serial and version are nonsense.
     *
     * A `numChars` of 0 means "no string present" and consumes only the length byte -
     * distinct from a 1, which means an empty string plus its terminator.
     */
    fun string(): String {
        val numChars = u8()
        if (numChars == 0) return ""

        require(numChars * 2)
        val sb = StringBuilder(numChars - 1)
        for (i in 0 until numChars) {
            val codeUnit = u16()
            // The final code unit is the null terminator: consumed, not appended.
            if (i < numChars - 1) sb.append(codeUnit.toChar())
        }
        return sb.toString()
    }

    /** PTP array: u32 element count followed by that many u16 elements. */
    fun u16Array(): IntArray {
        val count = u32()
        checkArrayCount(count, elementSize = 2)
        return IntArray(count.toInt()) { u16() }
    }

    /** PTP array: u32 element count followed by that many u32 elements. */
    fun u32Array(): LongArray {
        val count = u32()
        checkArrayCount(count, elementSize = 4)
        return LongArray(count.toInt()) { u32() }
    }

    fun bytes(count: Int): ByteArray {
        require(count)
        val out = data.copyOfRange(position, position + count)
        position += count
        return out
    }

    fun skip(count: Int) {
        require(count)
        position += count
    }

    /**
     * A corrupt or misaligned array count is the loudest symptom of a parser that has
     * drifted off-offset - typically because of P-03 upstream. Catching it here with the
     * offset in the message points straight at the real cause.
     */
    private fun checkArrayCount(count: Long, elementSize: Int) {
        if (count < 0 || count > MAX_ARRAY_ELEMENTS) {
            throw PtpException.Malformed(
                "Implausible array count $count at offset ${position - 4}. " +
                    "This usually means the cursor drifted earlier in the payload - check string parsing (P-03).",
            )
        }
        require((count * elementSize).toInt())
    }

    private companion object {
        /** No legitimate PTP dataset has a million-element array. */
        const val MAX_ARRAY_ELEMENTS = 1_000_000L
    }
}

/** Little-endian writer for building command containers and property payloads. */
class PtpWriter(initialCapacity: Int = 64) {

    private var buffer = ByteArray(initialCapacity)
    private var length = 0

    val size: Int get() = length

    private fun ensure(extra: Int) {
        if (length + extra > buffer.size) {
            buffer = buffer.copyOf(maxOf(buffer.size * 2, length + extra))
        }
    }

    fun u8(value: Int) = apply {
        ensure(1)
        buffer[length++] = (value and 0xFF).toByte()
    }

    fun u16(value: Int) = apply {
        ensure(2)
        buffer[length++] = (value and 0xFF).toByte()
        buffer[length++] = ((value ushr 8) and 0xFF).toByte()
    }

    fun u32(value: Long) = apply {
        ensure(4)
        for (i in 0 until 4) {
            buffer[length++] = ((value ushr (8 * i)) and 0xFF).toByte()
        }
    }

    fun u32(value: Int) = u32(value.toLong() and 0xFFFFFFFFL)

    fun bytes(value: ByteArray) = apply {
        ensure(value.size)
        value.copyInto(buffer, length)
        length += value.size
    }

    /** Writes a PTP string with the character count convention described in [PtpReader.string]. */
    fun string(value: String) = apply {
        if (value.isEmpty()) {
            u8(0)
            return@apply
        }
        u8(value.length + 1) // + null terminator
        value.forEach { u16(it.code) }
        u16(0)
    }

    fun toByteArray(): ByteArray = buffer.copyOf(length)
}
