package com.srisarani.fotozenai.dnp

import android.os.Handler
import io.flutter.plugin.common.EventChannel

/**
 * Throttles DNP USB print progress events before they reach Flutter's EventChannel.
 */
internal class DnpPrintProgressEmitter(
    private val mainHandler: Handler,
    private var sinkProvider: () -> EventChannel.EventSink?,
) {
    private var lastEmittedProgressStage: String? = null
    private var lastProgressEmitMs = 0L
    private var pendingProgress: PendingProgress? = null
    private var progressFlushRunnable: Runnable? = null

    fun emit(stage: String, message: String, progress: Double?) {
        mainHandler.post {
            val now = System.currentTimeMillis()
            val stageChanged = stage != lastEmittedProgressStage
            val terminal = stage == "complete"

            if (stageChanged || terminal || now - lastProgressEmitMs >= 150) {
                progressFlushRunnable?.let { mainHandler.removeCallbacks(it) }
                progressFlushRunnable = null
                pendingProgress = null
                dispatch(stage, message, progress)
                return@post
            }

            pendingProgress = PendingProgress(stage, message, progress)
            if (progressFlushRunnable != null) return@post

            val delay = (150 - (now - lastProgressEmitMs)).coerceAtLeast(0)
            progressFlushRunnable = Runnable {
                progressFlushRunnable = null
                val pending = pendingProgress ?: return@Runnable
                pendingProgress = null
                dispatch(pending.stage, pending.message, pending.progress)
            }
            mainHandler.postDelayed(progressFlushRunnable!!, delay.toLong())
        }
    }

    private fun dispatch(stage: String, message: String, progress: Double?) {
        lastEmittedProgressStage = stage
        lastProgressEmitMs = System.currentTimeMillis()
        sinkProvider()?.success(
            mapOf(
                "stage" to stage,
                "message" to message,
                "progress" to progress,
            ),
        )
    }

    private data class PendingProgress(
        val stage: String,
        val message: String,
        val progress: Double?,
    )
}
