package com.srisarani.fotozenai.canon.ptp

/**
 * Typed PTP failures.
 *
 * Every one carries enough context to diagnose from a log line alone - there is rarely a
 * debugger attached when these fire, and reproducing them needs the camera in a particular
 * state.
 */
sealed class PtpException(message: String, cause: Throwable? = null) : Exception(message, cause) {

    /** The camera returned a response code other than OK. */
    class OperationFailed(
        val operationCode: Int,
        val responseCode: Int,
        val parameters: LongArray = LongArray(0),
    ) : PtpException(
        "${PtpOperation.name(operationCode)} failed: ${PtpResponse.name(responseCode)}" +
            (if (PtpResponse.isVendorSpecific(responseCode)) " (Canon vendor code)" else "") +
            (if (parameters.isNotEmpty()) " params=" + parameters.joinToString { "0x%08X".format(it) } else ""),
    ) {
        val isBusy: Boolean get() = responseCode == PtpResponse.DEVICE_BUSY

        /**
         * Canon's "not ready yet" (`P-21`). Transient in the same way [isBusy] is — the
         * subsystem is starting, not broken — so callers that retry on busy must retry on
         * this too, or live view gives up during its own warm-up.
         */
        val isNotReady: Boolean get() = responseCode == PtpResponse.CANON_EOS_NOT_READY

        /** True for any response worth retrying rather than surfacing as a failure. */
        val isTransient: Boolean get() = isBusy || isNotReady
        val isUnsupported: Boolean get() = responseCode == PtpResponse.OPERATION_NOT_SUPPORTED
        val isSessionGone: Boolean
            get() = responseCode == PtpResponse.SESSION_NOT_OPEN ||
                responseCode == PtpResponse.INVALID_TRANSACTION_ID
    }

    /** A payload could not be parsed. Usually a cursor that drifted - see P-03. */
    class Malformed(message: String) : PtpException(message)

    /**
     * P-02: the response's transaction ID did not match the command we sent.
     *
     * This means the stream is offset - typically a previous operation timed out and its
     * response arrived late. Recovery is to drain the endpoint before continuing; carrying
     * on regardless means every subsequent response belongs to the previous command.
     */
    class TransactionMismatch(
        val expected: Long,
        val actual: Long,
        val operationCode: Int,
    ) : PtpException(
        "Transaction ID mismatch on ${PtpOperation.name(operationCode)}: expected $expected, got $actual. " +
            "The response stream is offset - draining before continuing (P-02).",
    )

    /** A container arrived with a type we did not expect at this point in the sequence. */
    class UnexpectedContainer(
        val expectedType: Int,
        val actual: PtpContainer,
    ) : PtpException(
        "Expected a ${PtpContainerType.name(expectedType)} container but got $actual",
    )

    /** The session was not open, or was closed underneath us. */
    class NotOpen : PtpException("No PTP session is open")
}
