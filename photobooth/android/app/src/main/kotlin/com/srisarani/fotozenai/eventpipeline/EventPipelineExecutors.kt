package com.srisarani.fotozenai.eventpipeline

import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.ThreadFactory
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Dedicated threads for the event pipeline's stages.
 *
 * Each stage gets its own lane so none can block another, and so **none of them
 * can block capture**: a PTP or CCAPI shutter must never wait behind a frame
 * composite. Nothing here touches the platform thread, so the UI stays
 * responsive while the queue works.
 *
 * Concurrency across lanes, sequence within each — which is exactly what the
 * hardware allows:
 *
 * - [ai] is network-bound and mostly idle waiting on the server, so a small pool
 *   overlaps requests without spending CPU.
 * - [frame] and [import] each hold a full-resolution bitmap, so they are single
 *   threaded and additionally share [bitmapPermit].
 * - [print] is single by necessity: there is one printer, and interleaving jobs
 *   on it would corrupt output.
 */
object EventPipelineExecutors {
    private const val TAG = "EventPipelineExec"

    /**
     * A 24 MP ARGB_8888 bitmap is roughly 96 MB. Import and framing each hold
     * one, and on a 4 GB Amlogic box two at once is a real OOM — which would
     * surface as a random crash mid-event, the worst way to discover it.
     *
     * One permit means the two bitmap-heavy stages take turns. AI and print are
     * unaffected: AI waits on the network and print streams to the driver, so
     * genuine parallelism survives where it actually helps.
     */
    private val bitmapPermit = Semaphore(1, true)

    /** Card enumeration and byte sampling. Cheap, but still off the UI thread. */
    val io = named("evp-io", 1)

    /** Downscale during import. Bitmap-heavy — see [bitmapPermit]. */
    val import = named("evp-import", 1)

    /** Server generation. Pool of 2: the wait dominates, not the work. */
    val ai = named("evp-ai", 2)

    /** Frame compositing. Bitmap-heavy — see [bitmapPermit]. */
    val frame = named("evp-frame", 1)

    /** One printer, so strictly one job at a time. */
    val print = named("evp-print", 1)

    private fun named(
        prefix: String,
        threads: Int,
    ) = Executors.newFixedThreadPool(
        threads,
        object : ThreadFactory {
            private val count = AtomicInteger(0)

            override fun newThread(r: Runnable): Thread {
                // Named so a stall is identifiable in a thread dump rather than
                // being one of a dozen anonymous pool threads.
                return Thread(r, "$prefix-${count.incrementAndGet()}").apply {
                    // Below default so a busy queue never starves the UI or a
                    // camera callback.
                    priority = Thread.NORM_PRIORITY - 1
                    isDaemon = true
                }
            }
        },
    )

    /**
     * Runs [block] holding the large-bitmap permit.
     *
     * Callers that decode a full-resolution image must go through this, or the
     * memory guard is only advisory.
     */
    fun <T> withBitmapMemory(
        label: String,
        block: () -> T,
    ): T {
        val waited = System.currentTimeMillis()
        bitmapPermit.acquire()
        val queuedMs = System.currentTimeMillis() - waited
        if (queuedMs > 1000) {
            Log.d(TAG, "$label waited ${queuedMs}ms for bitmap memory")
        }
        try {
            return block()
        } finally {
            bitmapPermit.release()
        }
    }

    /** Snapshot for the diagnostics panel. */
    fun describe(): Map<String, Any?> =
        mapOf(
            "bitmapPermitsAvailable" to bitmapPermit.availablePermits(),
            "bitmapQueueLength" to bitmapPermit.queueLength,
            "lanes" to listOf("io", "import", "ai", "frame", "print"),
        )

    /**
     * Stops the lanes. Only for process teardown — the pipeline is expected to
     * outlive any single screen.
     */
    fun shutdown() {
        for (pool in listOf(io, import, ai, frame, print)) {
            pool.shutdown()
            try {
                if (!pool.awaitTermination(2, TimeUnit.SECONDS)) {
                    pool.shutdownNow()
                }
            } catch (e: InterruptedException) {
                Log.d(TAG, "shutdown interrupted: ${e.message}")
                pool.shutdownNow()
                Thread.currentThread().interrupt()
            }
        }
    }
}
