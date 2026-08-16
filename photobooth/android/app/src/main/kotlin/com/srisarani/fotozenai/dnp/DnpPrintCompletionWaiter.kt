package com.srisarani.fotozenai.dnp

import android.util.Log

/** Polls STATUS until a DNP print job finishes or fails. */
internal class DnpPrintCompletionWaiter(
    private val hooks: DnpPrintStatusHooks,
) {
    fun waitForPrintComplete() {
        val state = PrintWaitState()
        repeat(DnpPrintStatusHooks.MAX_STATUS_RETRIES) { attempt ->
            val status = hooks.parseStatus()
            Log.d(TAG, "Print wait poll $attempt: status=$status (active=${state.sawPrinterActive})")
            if (printPollFinished(state, status, attempt)) {
                return
            }
            Thread.sleep(1_000)
        }
        throw DnpPrinterException("Print timed out")
    }

    private fun printPollFinished(
        state: PrintWaitState,
        status: Int,
        attempt: Int,
    ): Boolean {
        markActive(state, status)
        if (shouldComplete(state, status)) {
            hooks.onProgress("complete", "Print finished", 1.0)
            return true
        }
        retryStartIfStuckIdle(state, status, attempt)
        if (status >= 1000) {
            throw DnpPrinterException(hooks.errorMessage(status))
        }
        return reportPrintWait(state, status, attempt)
    }

    private fun markActive(
        state: PrintWaitState,
        status: Int,
    ) {
        if (status == 1 || status == 500 || status == 510) {
            state.sawPrinterActive = true
            state.unreadableStatusCount = 0
        }
    }

    private fun shouldComplete(
        state: PrintWaitState,
        status: Int,
    ): Boolean {
        if (!state.sawPrinterActive) {
            return false
        }
        return status == 0 || status == 500 || status == 510
    }

    private fun retryStartIfStuckIdle(
        state: PrintWaitState,
        status: Int,
        attempt: Int,
    ) {
        if (status != 0 || state.sawPrinterActive) {
            return
        }
        if (!state.startRetried && attempt >= DnpPrintStatusHooks.MIN_START_POLLS) {
            retryStartCommand(state)
            return
        }
        if (state.startRetried &&
            attempt >= DnpPrintStatusHooks.MIN_START_POLLS + DnpPrintStatusHooks.START_RETRY_GRACE_POLLS
        ) {
            throw DnpPrinterException(
                "Print did not start — check media is loaded and printer is ready",
            )
        }
    }

    private fun retryStartCommand(state: PrintWaitState) {
        Log.w(TAG, "Printer still idle after job send; retrying CNTRL START")
        state.startRetried = true
        try {
            hooks.sendStartCommand()
            Thread.sleep(1_000)
        } catch (e: Exception) {
            Log.w(TAG, "CNTRL START retry failed: ${e.message}")
        }
    }

    private fun reportPrintWait(
        state: PrintWaitState,
        status: Int,
        attempt: Int,
    ): Boolean {
        if (status == -1) {
            return reportUnreadable(state, attempt)
        }
        if (status != 0) {
            state.unreadableStatusCount = 0
            emitPrinting(state, hooks.statusLabel(status), attempt)
        }
        return false
    }

    private fun reportUnreadable(
        state: PrintWaitState,
        attempt: Int,
    ): Boolean {
        state.unreadableStatusCount++
        if (state.unreadableStatusCount >= DnpPrintStatusHooks.UNREADABLE_STATUS_COMPLETE) {
            hooks.onProgress("complete", "Print sent — check printer output", 1.0)
            return true
        }
        emitPrinting(state, "Waiting for printer (status check limited)…", attempt)
        return false
    }

    private fun emitPrinting(
        state: PrintWaitState,
        label: String,
        attempt: Int,
    ) {
        if (label != state.lastReportedLabel || attempt == 0) {
            state.lastReportedLabel = label
            val fraction =
                0.90 + (attempt.toDouble() / DnpPrintStatusHooks.MAX_STATUS_RETRIES) * 0.09
            hooks.onProgress("printing", label, fraction.coerceAtMost(0.99))
        }
    }

    private class PrintWaitState {
        var lastReportedLabel: String? = null
        var unreadableStatusCount: Int = 0
        var sawPrinterActive: Boolean = false
        var startRetried: Boolean = false
    }

    companion object {
        private const val TAG = "DnpUsbPrinter"
    }
}
