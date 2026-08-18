package com.srisarani.fotozenai.canon.capture

import com.srisarani.fotozenai.canon.eos.EosCapture
import com.srisarani.fotozenai.canon.eos.EosEvent
import com.srisarani.fotozenai.canon.eos.EosEventCode
import com.srisarani.fotozenai.canon.eos.EosSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Decouples the shutter from the transfer.
 *
 * ## Why this exists
 *
 * A 24MP JPEG is ~7MB and takes roughly a second to pull over USB 2.0. If the shutter
 * waited for the transfer, shot-to-shot time would be release + transfer instead of just
 * release, roughly halving throughput for no reason. So: the camera fires, the
 * object-added event lands on the queue, and a worker drains it in the background.
 *
 * ## Duplicate handling
 *
 * Object handles are deduplicated within a session (`P-10`). A duplicate `ObjectAdded` -
 * or the same shot arriving as both `ObjectAdded` and `RequestObjectTransfer`, which some
 * bodies do - would otherwise download twice and, at M8, bill the transform API twice.
 */
class CaptureQueue(
    private val capture: EosCapture,
    private val eos: EosSession,
    private val store: ImageStore,
    private val scope: CoroutineScope,
) {

    sealed interface Item {
        val handle: Long

        data class Pending(override val handle: Long, val sizeBytes: Long, val filename: String) : Item
        data class Downloading(override val handle: Long, val bytesRead: Long, val bytesTotal: Long) : Item
        data class Done(override val handle: Long, val image: StoredImage, val elapsedMs: Long) : Item
        data class Failed(override val handle: Long, val reason: String) : Item
    }

    private val pending = Channel<Item.Pending>(capacity = Channel.BUFFERED)

    private val _state = MutableStateFlow<Item?>(null)
    val state: StateFlow<Item?> = _state.asStateFlow()

    /**
     * Completed captures.
     *
     * `replay = 1` because the UI subscriber is not guaranteed to be attached at the moment
     * a download finishes — the Activity may be recreating, or the queue itself may have
     * just been rebuilt by a reconnect (`C-18`). With no replay a completion emitted into
     * an empty subscriber list is silently discarded, and the image sits on disk with the
     * UI insisting nothing was captured. Replaying the most recent one costs a single
     * reference and makes a late subscriber correct instead of blind.
     */
    private val _completed = MutableSharedFlow<Item.Done>(replay = 1, extraBufferCapacity = 64)
    val completed: SharedFlow<Item.Done> = _completed.asSharedFlow()

    /**
     * Handle of the most recent [Item.Done], for seeding Activity-side dedup.
     *
     * Each new [CanonCaptureActivity] starts with an empty `consumedHandles` set, but
     * `completed` replays the last shot — without seeding, the first shutter of a
     * retake completes instantly with the previous session's file.
     */
    private var lastCompletedHandle: Long? = null

    /** Marks the replayed completion as already consumed (Back → POSE → capture again). */
    fun seedReplayInto(consumed: MutableSet<Long>) {
        lastCompletedHandle?.let { consumed += it }
    }

    /** Handles already seen this session. `P-10` deduplication. */
    private val seenHandles = mutableSetOf<Long>()

    var capturesCompleted: Int = 0
        private set
    var capturesFailed: Int = 0
        private set
    var duplicatesIgnored: Int = 0
        private set

    /** Timings for the M9 assessment: shutter → JPEG on disk. */
    val downloadTimingsMs = mutableListOf<Long>()

    fun start() {
        CanonLog.i("CaptureQueue started, storing to %s", store.rootPath())

        // Feed the queue from the event stream.
        scope.launch {
            eos.events.collect { event -> onEvent(event) }
        }

        // Drain it, one download at a time - the USB endpoint is serial anyway.
        scope.launch {
            while (isActive) {
                val item = pending.receive()
                downloadOne(item)
            }
        }
    }

    private fun onEvent(event: EosEvent) {
        when (event) {
            is EosEvent.ObjectAdded -> enqueue(event.objectHandle, event.sizeBytes, event.filename)

            // Some bodies ask the host to pull rather than announcing an addition. Treat
            // both as the same trigger; dedup makes handling both safe.
            is EosEvent.ObjectTransferRequested ->
                enqueue(event.objectHandle, event.sizeBytes, event.filename)

            is EosEvent.Unknown -> {
                // P-14: this body reports 0xC1A0/0xC1A1 which we cannot name yet, and its
                // event list lacks our assumed AfResult code. Log these prominently while
                // capture is exercised so the AF-completion code can be identified (C-02).
                if (event.code in AF_CANDIDATE_CODES) {
                    CanonLog.w(
                        "P-14 candidate: unnamed event %s during capture, payload=%s",
                        EosEventCode.name(event.code),
                        event.payload.joinToString(" ") { "%02X".format(it) },
                    )
                }
            }

            else -> Unit
        }
    }

    private fun enqueue(handle: Long, size: Long, filename: String) {
        if (!seenHandles.add(handle)) {
            duplicatesIgnored++
            CanonLog.d("Ignoring duplicate object handle 0x%08X (P-10)", handle)
            return
        }

        // Logged unconditionally: without this the happy path is silent, and a capture that
        // never reaches disk is indistinguishable from one the queue never saw at all.
        // That ambiguity cost a full debugging session on 2026-08-14.
        CanonLog.i("Queueing capture: handle=0x%08X %,d bytes", handle, size)

        if (!store.hasRoomFor(size)) {
            capturesFailed++
            val reason = "Insufficient disk space for ${size} bytes (I-11)"
            CanonLog.e(reason)
            _state.value = Item.Failed(handle, reason)
            return
        }

        val item = Item.Pending(handle, size, filename)
        _state.value = item
        val accepted = pending.trySend(item).isSuccess
        if (!accepted) {
            capturesFailed++
            CanonLog.e("Capture queue full, dropped handle 0x%08X", handle)
        }
    }

    private suspend fun downloadOne(item: Item.Pending) {
        try {
            _state.value = Item.Downloading(item.handle, 0, item.sizeBytes)

            val result = capture.download(item.handle, item.sizeBytes) { read, total ->
                _state.value = Item.Downloading(item.handle, read, total)
            }

            // ObjectAddedEx64 (what this body sends) carries no filename, so resolve it
            // now if we want one. Costs a single round trip and only after the bytes are
            // already safe - a failure here must never lose an image we have in hand.
            val filename = item.filename.ifBlank { capture.resolveFilename(item.handle) }

            val stored = store.writeOriginal(result.bytes, filename)
            capturesCompleted++
            downloadTimingsMs += result.elapsedMs

            val done = Item.Done(item.handle, stored, result.elapsedMs)
            _state.value = done
            lastCompletedHandle = item.handle
            _completed.tryEmit(done)
        } catch (e: Exception) {
            capturesFailed++
            CanonLog.e(e, "Download failed for handle 0x%08X", item.handle)
            _state.value = Item.Failed(item.handle, e.message ?: e.javaClass.simpleName)
        }
    }

    /** Median download time, for the M9 assessment. */
    fun medianDownloadMs(): Long =
        downloadTimingsMs.sorted().let { if (it.isEmpty()) 0 else it[it.size / 2] }

    fun summary(): String =
        "completed=$capturesCompleted failed=$capturesFailed duplicates=$duplicatesIgnored " +
            "medianDownload=${medianDownloadMs()}ms"

    private companion object {
        /**
         * Unnamed events observed on the 200D II (`P-14`). One of these is likely the AF
         * result, which `C-02` needs to distinguish AF failure from a dead event loop.
         */
        val AF_CANDIDATE_CODES = setOf(0xC1A0, 0xC1A1)
    }
}
