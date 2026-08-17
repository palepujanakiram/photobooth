package com.srisarani.fotozenai.dnp

/** Polls DNP STATUS until the printer is ready or a job finishes. */
internal class DnpPrintStatusMonitor(
    cmd: DnpCommand,
    onProgress: PrintProgressCallback,
    statusLabel: (Int) -> String,
    errorMessage: (Int) -> String,
    sendStartCommand: () -> Unit,
) {
    private val hooks =
        DnpPrintStatusHooks(
            cmd = cmd,
            onProgress = onProgress,
            statusLabel = statusLabel,
            errorMessage = errorMessage,
            sendStartCommand = sendStartCommand,
        )

    fun waitUntilReady() = DnpPrintReadyWaiter(hooks).waitUntilReady()

    fun waitForPrintComplete() = DnpPrintCompletionWaiter(hooks).waitForPrintComplete()
}
