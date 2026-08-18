package com.srisarani.fotozenai.canon.ptp

/**
 * A PTP-over-USB container.
 *
 * Wire format, little-endian, no padding:
 *
 * ```
 * offset  size  field
 *   0      4    length         total container size INCLUDING this 12-byte header
 *   4      2    type           1 Command, 2 Data, 3 Response, 4 Event
 *   6      2    code           opcode / response code / event code
 *   8      4    transactionId
 *  12      *    payload        command+response: up to 5 x u32 params. data: raw bytes.
 * ```
 *
 * The `length` field counting the header is worth internalising: reading `length` bytes of
 * payload rather than `length - 12` overruns by exactly one header on every single
 * transaction.
 */
data class PtpContainer(
    val type: Int,
    val code: Int,
    val transactionId: Long,
    val payload: ByteArray = EMPTY,
) {

    val totalLength: Int get() = PtpHeader.SIZE + payload.size

    /** Command and response payloads are up to five u32 parameters. */
    val parameters: LongArray
        get() {
            val count = minOf(payload.size / 4, PtpHeader.MAX_PARAMS)
            val reader = PtpReader(payload)
            return LongArray(count) { reader.u32() }
        }

    fun parameter(index: Int): Long = parameters.getOrElse(index) { 0L }

    fun toByteArray(): ByteArray {
        val writer = PtpWriter(totalLength)
        writer.u32(totalLength.toLong())
        writer.u16(type)
        writer.u16(code)
        writer.u32(transactionId)
        writer.bytes(payload)
        return writer.toByteArray()
    }

    val isOk: Boolean get() = type == PtpContainerType.RESPONSE && code == PtpResponse.OK

    override fun toString(): String {
        val codeName = when (type) {
            PtpContainerType.RESPONSE -> PtpResponse.name(code)
            else -> PtpOperation.name(code)
        }
        val paramText = if (type == PtpContainerType.DATA) {
            "${payload.size}B"
        } else {
            parameters.joinToString { "0x%08X".format(it) }.ifEmpty { "-" }
        }
        return "${PtpContainerType.name(type)}/$codeName txn=$transactionId [$paramText]"
    }

    // data class with a ByteArray needs these written out
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PtpContainer) return false
        return type == other.type &&
            code == other.code &&
            transactionId == other.transactionId &&
            payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = type
        result = 31 * result + code
        result = 31 * result + transactionId.hashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }

    companion object {
        private val EMPTY = ByteArray(0)

        /** Builds a command container from up to five parameters. */
        fun command(code: Int, transactionId: Long, vararg params: Long): PtpContainer {
            require(params.size <= PtpHeader.MAX_PARAMS) {
                "PTP allows at most ${PtpHeader.MAX_PARAMS} parameters, got ${params.size}"
            }
            val writer = PtpWriter(params.size * 4)
            params.forEach { writer.u32(it) }
            return PtpContainer(PtpContainerType.COMMAND, code, transactionId, writer.toByteArray())
        }

        fun data(code: Int, transactionId: Long, payload: ByteArray): PtpContainer =
            PtpContainer(PtpContainerType.DATA, code, transactionId, payload)

        /**
         * Parses a container from raw bytes.
         *
         * Validates the declared length against what actually arrived. A mismatch is a
         * hard error rather than a best-effort parse: silently accepting a truncated
         * container is P-08, the failure mode where nothing errors and the data is simply
         * wrong.
         */
        fun parse(bytes: ByteArray, offset: Int = 0): PtpContainer {
            val available = bytes.size - offset
            if (available < PtpHeader.SIZE) {
                throw PtpException.Malformed(
                    "Container header truncated: got $available bytes, need ${PtpHeader.SIZE}",
                )
            }

            val reader = PtpReader(bytes, offset)
            val declaredLength = reader.u32()
            val type = reader.u16()
            val code = reader.u16()
            val transactionId = reader.u32()

            if (declaredLength < PtpHeader.SIZE) {
                throw PtpException.Malformed(
                    "Container declares length $declaredLength, less than the ${PtpHeader.SIZE}-byte header",
                )
            }
            if (declaredLength > available) {
                throw PtpException.Malformed(
                    "Container declares length $declaredLength but only $available bytes arrived " +
                        "(truncated transfer - see P-08)",
                )
            }

            val payloadSize = (declaredLength - PtpHeader.SIZE).toInt()
            val payload = if (payloadSize > 0) reader.bytes(payloadSize) else EMPTY

            return PtpContainer(type, code, transactionId, payload)
        }

        /** Reads just the declared length from a header, for sizing the following read. */
        fun peekLength(bytes: ByteArray, offset: Int = 0): Long {
            if (bytes.size - offset < 4) {
                throw PtpException.Malformed("Need 4 bytes to read a container length")
            }
            return PtpReader(bytes, offset).u32()
        }
    }
}
