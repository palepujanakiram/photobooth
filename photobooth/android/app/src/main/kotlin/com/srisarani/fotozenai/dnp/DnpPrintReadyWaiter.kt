package com.srisarani.fotozenai.dnp

/** Waits until the DNP printer can accept a new job. */
internal class DnpPrintReadyWaiter(
    private val hooks: DnpPrintStatusHooks,
) {
    fun waitUntilReady() {
        var lastReportedMessage: String? = null
        var unreadableStatusCount = 0
        repeat(DnpPrintStatusHooks.MAX_STATUS_RETRIES) {
            when (val step = readyStep(hooks.parseStatus(), unreadableStatusCount, lastReportedMessage)) {
                ReadyStep.Finished -> {
                    return
                }

                is ReadyStep.KeepWaiting -> {
                    lastReportedMessage = step.message
                    unreadableStatusCount = step.unreadable
                }
            }
            Thread.sleep(1_000)
        }
        throw DnpPrinterException("Printer not ready (timeout)")
    }

    private fun readyStep(
        status: Int,
        unreadable: Int,
        lastMessage: String?,
    ): ReadyStep =
        when (status) {
            0, 1 -> {
                readyWhenActive(status, unreadable, lastMessage)
            }

            -1 -> {
                readyWhenUnreadable(unreadable, lastMessage)
            }

            500, 510, 900 -> {
                reportReadyMessage(hooks.statusLabel(status), lastMessage, unreadable)
            }

            1000, 1010, 1100, 1200, 1300, 1400 -> {
                throw DnpPrinterException(hooks.errorMessage(status))
            }

            else -> {
                throw DnpPrinterException("Printer error: $status")
            }
        }

    private fun readyWhenActive(
        status: Int,
        unreadable: Int,
        lastMessage: String?,
    ): ReadyStep {
        val buffers = hooks.cmd.sendResponseCommand("INFO", "FREE_PBUFFER")
        val available = parseFreeBufferCount(buffers)
        if (available >= 1 || (available < 0 && status == 0)) {
            hooks.onProgress("wait_ready", "Printer ready", 0.30)
            return ReadyStep.Finished
        }
        return reportReadyMessage("Waiting for printer buffer…", lastMessage, unreadable)
    }

    private fun readyWhenUnreadable(
        unreadable: Int,
        lastMessage: String?,
    ): ReadyStep {
        val next = unreadable + 1
        if (next >= DnpPrintStatusHooks.READY_UNREADABLE_PROCEED) {
            hooks.onProgress(
                "wait_ready",
                "Proceeding — status check limited on this USB host",
                0.30,
            )
            return ReadyStep.Finished
        }
        return reportReadyMessage("Reading printer status…", lastMessage, next)
    }

    private fun reportReadyMessage(
        msg: String,
        lastMessage: String?,
        unreadable: Int,
    ): ReadyStep {
        if (msg != lastMessage) {
            hooks.onProgress("wait_ready", msg, null)
        }
        return ReadyStep.KeepWaiting(msg, unreadable)
    }

    private fun parseFreeBufferCount(raw: String): Int {
        DnpCommand.parseIntResponse(raw.drop(3))?.let { return it }
        DnpCommand.parseIntResponse(raw)?.let { return it }
        return -1
    }

    private sealed class ReadyStep {
        data object Finished : ReadyStep()

        data class KeepWaiting(
            val message: String?,
            val unreadable: Int,
        ) : ReadyStep()
    }
}
