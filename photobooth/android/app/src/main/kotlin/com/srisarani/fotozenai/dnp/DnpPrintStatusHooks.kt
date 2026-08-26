package com.srisarani.fotozenai.dnp

/** Shared STATUS polling helpers for DNP USB print waits. */
internal class DnpPrintStatusHooks(
    val cmd: DnpCommand,
    val onProgress: PrintProgressCallback,
    val statusLabel: (Int) -> String,
    val errorMessage: (Int) -> String,
    val sendStartCommand: () -> Unit,
) {
    fun parseStatus(): Int {
        val response = cmd.queryResponse("STATUS", "") ?: return -1
        return DnpCommand.parseIntResponse(response) ?: -1
    }

    companion object {
        const val MAX_STATUS_RETRIES = 120
        const val UNREADABLE_STATUS_COMPLETE = 8
        const val READY_UNREADABLE_PROCEED = 5
        /**
         * Idle polls to tolerate before re-sending `CNTRL START`.
         *
         * Was 3, which cost ~4s on every print. The START embedded in the job stream is
         * sent (`DnpUsbPrinter.sendJobChunks`) but this printer never acts on it: two
         * traced prints on the DS-RX1HS both sat at `status=0 (active=false)` for polls
         * 0-3, then went active immediately after the standalone retry. So the retry is
         * the thing that actually starts the job, and the wait in front of it is dead time.
         *
         * One poll of grace rather than none. Combined with the 1.5s of settling already
         * spent after the stream (500ms in sendJobChunks, 1s before polling), that leaves
         * ~2.6s for a printer that is merely slow to pick the job up out of its buffer,
         * which re-sending START underneath would be the wrong answer for.
         */
        const val MIN_START_POLLS = 1
        const val START_RETRY_GRACE_POLLS = 10
    }
}
