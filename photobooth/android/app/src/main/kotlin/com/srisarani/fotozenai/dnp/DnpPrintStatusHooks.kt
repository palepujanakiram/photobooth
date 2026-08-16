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
        const val MIN_START_POLLS = 3
        const val START_RETRY_GRACE_POLLS = 10
    }
}
