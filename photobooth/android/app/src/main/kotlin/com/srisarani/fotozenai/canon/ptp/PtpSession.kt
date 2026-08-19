package com.srisarani.fotozenai.canon.ptp

import com.srisarani.fotozenai.canon.usb.UsbTransport
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Drives the PTP command / data / response sequence over a [UsbTransport].
 *
 * ## Threading
 *
 * **Not thread-safe, by design.** Every call must happen on the single USB dispatcher
 * (`CameraSessionManager.usbDispatcher`). PTP is strictly serialised with a monotonic
 * transaction ID; two concurrent callers interleave their containers and corrupt the
 * session. Adding a lock here would hide that rather than fix it - the constraint is that
 * there is exactly one caller, and the architecture enforces it.
 *
 * ## The transaction sequence
 *
 * ```
 * host -> camera   Command container   (opcode + up to 5 params)
 * host -> camera   Data container      (optional, only for operations that send data)
 * camera -> host   Data container      (optional, only for operations that return data)
 * camera -> host   Response container  (always)
 * ```
 *
 * Whether a data phase occurs is a property of the operation, but we do not hardcode a
 * table of which operations have one. Instead [transact] reads a container and inspects
 * its *type*: a Data container is consumed as data, a Response container ends the
 * transaction. That is both simpler and more robust than a lookup table that would need a
 * row for every vendor opcode.
 */
class PtpSession(private val transport: UsbTransport) {

    /**
     * Monotonic transaction ID.
     *
     * Starts at 0, which is what `OpenSession` uses. Wraps to 1 rather than 0 at the top
     * of the range, since 0xFFFFFFFF is reserved and 0 belongs to OpenSession.
     */
    private var nextTransactionId: Long = 0

    var sessionId: Int = 0
        private set

    var isOpen: Boolean = false
        private set

    /** Cached result of the last [getDeviceInfo] call. Named to avoid clashing with it. */
    var cachedDeviceInfo: PtpDeviceInfo? = null
        private set

    /** Diagnostics: how many times P-02 recovery has fired. Non-zero is worth investigating. */
    var transactionMismatchCount: Int = 0
        private set

    // -------------------------------------------------------------- session

    /**
     * `GetDeviceInfo` works before a session is open - that is deliberate in the standard,
     * and it is how we learn what the body supports before committing to anything.
     */
    fun getDeviceInfo(timeoutMs: Int? = null): PtpDeviceInfo {
        val result = transact(PtpOperation.GET_DEVICE_INFO, timeoutMs = timeoutMs)
        val payload = result.data ?: throw PtpException.Malformed("GetDeviceInfo returned no data phase")
        val info = PtpDeviceInfo.parse(payload)
        cachedDeviceInfo = info
        CanonLog.i("DeviceInfo: %s", info)
        return info
    }

    /**
     * Opens a session. [sessionId] must be non-zero.
     *
     * A `SessionAlreadyOpen` response is treated as success: it means the camera still
     * believes a previous session is live, which happens after an app crash or an
     * unclean detach. Failing here would leave the user unable to reconnect without
     * power-cycling the camera.
     */
    fun openSession(sessionId: Int = 1) {
        require(sessionId != 0) { "PTP session ID must be non-zero" }

        nextTransactionId = 0
        val result = try {
            transact(PtpOperation.OPEN_SESSION, sessionId.toLong())
        } catch (e: PtpException.OperationFailed) {
            if (e.responseCode == PtpResponse.SESSION_ALREADY_OPEN) {
                CanonLog.w("Session already open on the camera - adopting it (previous run exited uncleanly)")
                this.sessionId = sessionId
                isOpen = true
                nextTransactionId = 1
                return
            }
            throw e
        }

        this.sessionId = sessionId
        isOpen = true
        CanonLog.i("PTP session %d opened (response %s)", sessionId, PtpResponse.name(result.responseCode))
    }

    /**
     * Closes the session. Never throws.
     *
     * Called from teardown paths - a cable pull, an app exit - where the camera may already
     * be gone. Throwing here would turn an orderly shutdown into a crash.
     */
    fun closeSession() {
        if (!isOpen) return
        runCatching { transact(PtpOperation.CLOSE_SESSION) }
            .onFailure { CanonLog.w(it, "CloseSession failed (camera may already be gone)") }
        isOpen = false
        sessionId = 0
        CanonLog.i("PTP session closed")
    }

    // ------------------------------------------------------------- transact

    data class Result(
        val responseCode: Int,
        val responseParameters: LongArray,
        val data: ByteArray?,
    ) {
        fun parameter(index: Int): Long = responseParameters.getOrElse(index) { 0L }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Result) return false
            return responseCode == other.responseCode &&
                responseParameters.contentEquals(other.responseParameters) &&
                (data?.contentEquals(other.data ?: ByteArray(0)) ?: (other.data == null))
        }

        override fun hashCode(): Int {
            var result = responseCode
            result = 31 * result + responseParameters.contentHashCode()
            result = 31 * result + (data?.contentHashCode() ?: 0)
            return result
        }
    }

    /**
     * Runs one complete PTP transaction.
     *
     * @param outgoingData payload for operations that send data to the camera.
     * @param expectData hint only; the actual decision is made from the container type
     *   that comes back.
     * @throws PtpException.OperationFailed when the response code is not OK.
     */
    fun transact(
        operationCode: Int,
        vararg params: Long,
        outgoingData: ByteArray? = null,
        timeoutMs: Int? = null,
    ): Result {
        val transactionId = allocateTransactionId()
        val started = System.nanoTime()

        val command = PtpContainer.command(operationCode, transactionId, *params)
        logOut(command)
        transport.write(command.toByteArray())

        if (outgoingData != null) {
            val dataContainer = PtpContainer.data(operationCode, transactionId, outgoingData)
            logOut(dataContainer)
            transport.write(dataContainer.toByteArray())
        }

        var incomingData: ByteArray? = null
        var response: PtpContainer? = null

        // Read containers until the Response arrives. At most two iterations in practice
        // (one Data, one Response), but the loop is bounded rather than assumed.
        var iterations = 0
        while (response == null) {
            if (++iterations > MAX_CONTAINERS_PER_TRANSACTION) {
                throw PtpException.Malformed(
                    "More than $MAX_CONTAINERS_PER_TRANSACTION containers in one transaction - " +
                        "the stream is almost certainly desynchronised",
                )
            }

            val container = readContainer(operationCode, transactionId, timeoutMs)
            when (container.type) {
                PtpContainerType.DATA -> {
                    if (incomingData != null) {
                        CanonLog.w("Second data container in one transaction; concatenating")
                        incomingData += container.payload
                    } else {
                        incomingData = container.payload
                    }
                }

                PtpContainerType.RESPONSE -> response = container

                else -> throw PtpException.UnexpectedContainer(PtpContainerType.RESPONSE, container)
            }
        }

        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        logIn(response, incomingData?.size ?: 0, elapsedMs)

        if (response.code != PtpResponse.OK) {
            throw PtpException.OperationFailed(operationCode, response.code, response.parameters)
        }

        return Result(response.code, response.parameters, incomingData)
    }

    /**
     * Like [transact] but returns the failing response instead of throwing.
     *
     * Used where a non-OK response is an expected outcome rather than an error - probing
     * whether an operation is supported, or tolerating `DeviceBusy` in a retry loop (P-07).
     */
    fun tryTransact(operationCode: Int, vararg params: Long): kotlin.Result<Result> =
        runCatching { transact(operationCode, *params) }

    // ------------------------------------------------------------- internals

    /**
     * Reads one container, assembling the header and payload.
     *
     * The two-step read is what makes ZLP handling correct: the header declares the total
     * length, so the payload read can be given an exact `expectedLength`, which is what
     * lets [UsbTransport] know whether to drain a trailing zero-length packet (P-01).
     */
    private fun readContainer(operationCode: Int, expectedTransactionId: Long, timeoutMs: Int?): PtpContainer {
        val read = if (timeoutMs != null) {
            transport.readTransfer(timeoutMs = timeoutMs)
        } else {
            transport.readTransfer()
        }

        if (read.size < PtpHeader.SIZE) {
            throw PtpException.Malformed(
                "Container header truncated: ${read.size} bytes (expected at least ${PtpHeader.SIZE}). " +
                    "A zero-length read here usually means a stale ZLP was left by the previous " +
                    "transfer - see P-01.",
            )
        }

        val declaredLength = PtpContainer.peekLength(read.data)
        var buffer = read.data

        // The device may end the transfer at a packet boundary before the whole container
        // has arrived. Keep reading until we have the declared length.
        if (declaredLength > buffer.size) {
            val remaining = (declaredLength - buffer.size).toInt()
            val rest = transport.readTransfer(expectedLength = remaining)
            if (rest.size != remaining) {
                // Dump the bytes. This failure has been chased three times on hardware from
                // the declared length alone (U-17), and that number cannot distinguish the
                // competing explanations: leftovers from the previous session, a response to
                // an earlier transaction, or a body that is powering down and replying with
                // rubbish. The first 32 bytes settle it in one look.
                throw PtpException.Malformed(
                    "Container truncated: declared $declaredLength, " +
                        "assembled ${buffer.size + rest.size}. " +
                        "op=0x${operationCode.toString(16)} " +
                        "expectedTxn=$expectedTransactionId " +
                        "head=${hexPreview(buffer)} tail=${hexPreview(rest.data)}",
                )
            }
            buffer += rest.data
        }

        val container = PtpContainer.parse(buffer)

        // -------- P-02: validate the transaction ID on EVERY response, never assume --------
        //
        // A late response from a previously timed-out operation offsets the entire stream.
        // Draining here is what makes the session recoverable instead of permanently
        // desynchronised.
        if (container.type != PtpContainerType.EVENT && container.transactionId != expectedTransactionId) {
            transactionMismatchCount++
            val discarded = transport.drain()
            CanonLog.e(
                "P-02 transaction mismatch on %s: expected %d got %d. Drained %dB.",
                PtpOperation.name(operationCode),
                expectedTransactionId,
                container.transactionId,
                discarded,
            )
            throw PtpException.TransactionMismatch(
                expected = expectedTransactionId,
                actual = container.transactionId,
                operationCode = operationCode,
            )
        }

        return container
    }

    private fun allocateTransactionId(): Long {
        val id = nextTransactionId
        nextTransactionId = if (nextTransactionId >= MAX_TRANSACTION_ID) 1 else nextTransactionId + 1
        return id
    }

    /**
     * Every transaction is logged in both directions (plan section 0).
     *
     * This is not optional instrumentation to add when something breaks - by the time
     * something breaks, the evidence is gone. It runs from M1 onward, always.
     */
    private fun logOut(container: PtpContainer) {
        CanonLog.d("--> %s", container)
    }

    /** First [max] bytes as hex, for failures where the parsed values are meaningless. */
    private fun hexPreview(bytes: ByteArray, max: Int = HEX_PREVIEW_BYTES): String {
        if (bytes.isEmpty()) return "<empty>"
        val shown = bytes.take(max).joinToString(" ") { "%02X".format(it) }
        return if (bytes.size > max) "$shown … (${bytes.size}B)" else "$shown (${bytes.size}B)"
    }

    private fun logIn(response: PtpContainer, dataBytes: Int, elapsedMs: Long) {
        if (dataBytes > 0) {
            CanonLog.d("<-- %s +%dB data (%dms)", response, dataBytes, elapsedMs)
        } else {
            CanonLog.d("<-- %s (%dms)", response, elapsedMs)
        }
    }

    private companion object {
        /** Enough to cover a 12-byte PTP header plus the start of its payload. */
        const val HEX_PREVIEW_BYTES = 32

        /** 0xFFFFFFFF is reserved by the standard. */
        const val MAX_TRANSACTION_ID = 0xFFFFFFFEL

        /** One Data plus one Response is normal; more means the stream has drifted. */
        const val MAX_CONTAINERS_PER_TRANSACTION = 8
    }
}
