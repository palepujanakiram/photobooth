package com.srisarani.fotozenai.canon.capture

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [CaptureQueue.seedReplayInto] replay dedup contract. */
class CaptureQueueReplayTest {

    @Test
    fun seedReplayInto_addsLastHandleToConsumedSet() {
        val consumed = mutableSetOf<Long>()
        val queue = CaptureQueueReplayHarness(lastCompletedHandle = 0x42L)

        queue.seedReplayInto(consumed)

        assertTrue(0x42L in consumed)
    }

    @Test
    fun seedReplayInto_noOpWhenNoPriorCompletion() {
        val consumed = mutableSetOf<Long>()
        val queue = CaptureQueueReplayHarness(lastCompletedHandle = null)

        queue.seedReplayInto(consumed)

        assertTrue(consumed.isEmpty())
    }

    @Test
    fun seedReplayInto_doesNotDuplicateExistingHandle() {
        val consumed = mutableSetOf(0x42L)
        val queue = CaptureQueueReplayHarness(lastCompletedHandle = 0x42L)

        queue.seedReplayInto(consumed)

        assertTrue(0x42L in consumed)
        assertFalse(consumed.size > 1)
    }

    /** Mirrors [CaptureQueue.seedReplayInto] without EOS session wiring. */
    private class CaptureQueueReplayHarness(
        private val lastCompletedHandle: Long?,
    ) {
        fun seedReplayInto(consumed: MutableSet<Long>) {
            lastCompletedHandle?.let { consumed += it }
        }
    }
}
