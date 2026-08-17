package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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
 * The Canon EOS remote-mode handshake and event loop.
 *
 * ## Why this is the highest-risk milestone
 *
 * An EOS body will happily accept commands without ever entering remote mode. Nothing
 * fails. Capture simply never completes, and the failure looks exactly like a bug in the
 * capture code - which is why the plan says: **if capture hangs, suspect the event loop
 * before the capture code (C-01).**
 *
 * Three things must all be true, and all three are easy to get subtly wrong:
 *
 * 1. `SetRemoteMode` succeeded
 * 2. `SetEventMode` succeeded
 * 3. **`GetEvent` is being polled continuously and the results drained**
 *
 * Point 3 is the one people miss. The camera does not push events; it queues them and
 * expects the host to drain the queue. A host that stops draining is treated as gone.
 * That is why [start] refuses to return success unless the loop is actually running, and
 * why [consecutiveFailures] is surfaced rather than swallowed.
 */
class EosSession(
    private val ptp: PtpSession,
    private val scope: CoroutineScope,
    private val config: Config = Config(),
) {

    data class Config(
        /**
         * How often to poll `GetEvent`.
         *
         * 200ms is a deliberate compromise. Faster starves the single USB thread that
         * capture and live view also need; slower makes capture feel laggy, because the
         * object-added event is what tells M4 the shot is ready.
         */
        val pollIntervalMs: Long = 200,

        /**
         * Keepalive interval. Well inside any plausible idle timeout.
         *
         * Sent regardless of the camera's auto-power-off menu setting, because "disabled"
         * is not fully disabled (C-03).
         */
        val keepAliveIntervalMs: Long = 10_000,

        /** Consecutive poll failures before the session is declared wedged (O-06). */
        val maxConsecutiveFailures: Int = 10,

        /** Remote mode argument. libgphoto2 uses 1 for EOS bodies - VERIFY against ptp.h. */
        val remoteModeValue: Long = 1,

        /** Event mode argument. libgphoto2 uses 1 - VERIFY against ptp.h. */
        val eventModeValue: Long = 1,
    )

    enum class State { Stopped, Starting, Running, Wedged }

    private val _state = MutableStateFlow(State.Stopped)
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Replayed, deliberately.
     *
     * The camera dumps its **entire** settings state in the first `GetEvent` after the
     * handshake - the 200D II sent 11 KB of `PropValueChanged` in one response. Anything
     * that subscribes after that (the settings catalogue is constructed moments later)
     * would otherwise see nothing until a setting happened to change, and the control
     * panel would sit empty on a perfectly healthy camera. Verified on hardware
     * 2026-08-13: with `replay = 0` the M7 panel never populated.
     *
     * For property state, replaying stale events is exactly right - the newest value for
     * each property is precisely what a late subscriber needs.
     *
     * `extraBufferCapacity` absorbs a burst without suspending the loop; a suspended emit
     * would stall polling, which is the one thing this class exists to prevent.
     */
    private val _events = MutableSharedFlow<EosEvent>(
        replay = 256,
        extraBufferCapacity = 256,
    )
    val events: SharedFlow<EosEvent> = _events.asSharedFlow()

    private var pollJob: Job? = null
    private var keepAliveJob: Job? = null

    /** Diagnostics, surfaced rather than swallowed - see the class doc. */
    var eventsReceived: Long = 0
        private set
    var pollCount: Long = 0
        private set
    var consecutiveFailures: Int = 0
        private set
    var lastEventAtMillis: Long = 0
        private set

    // ------------------------------------------------------------------ start

    /**
     * Performs the handshake and starts the event loop.
     *
     * @throws PtpException if either mode command fails - there is no point continuing,
     *   and failing loudly here is far kinder than a silent hang at M4.
     */
    fun start() {
        if (_state.value == State.Running || _state.value == State.Starting) {
            CanonLog.d("EosSession already started")
            return
        }
        _state.value = State.Starting

        try {
            CanonLog.i("EOS handshake: SetRemoteMode(%d)", config.remoteModeValue)
            ptp.transact(CanonEosOperation.SET_REMOTE_MODE, config.remoteModeValue)

            CanonLog.i("EOS handshake: SetEventMode(%d)", config.eventModeValue)
            ptp.transact(CanonEosOperation.SET_EVENT_MODE, config.eventModeValue)
        } catch (e: PtpException) {
            _state.value = State.Stopped
            CanonLog.e(e, "EOS handshake failed - remote mode not entered. M4 cannot work until this passes.")
            throw e
        }

        startEventLoop()
        startKeepAlive()
        _state.value = State.Running
        CanonLog.i("EOS remote mode active, event loop polling every %dms", config.pollIntervalMs)
    }

    /**
     * The event loop.
     *
     * Non-negotiable property: **this loop must not be able to die.** Every failure mode
     * is caught and counted. Only a cancellation (deliberate shutdown) or crossing
     * [Config.maxConsecutiveFailures] stops it, and the latter transitions to
     * [State.Wedged] so the watchdog in M11 can re-initialise rather than leaving the app
     * silently broken.
     */
    private fun startEventLoop() {
        pollJob = scope.launch {
            while (isActive) {
                try {
                    val events = pollOnce()
                    consecutiveFailures = 0
                    events.forEach { event ->
                        eventsReceived++
                        lastEventAtMillis = System.currentTimeMillis()
                        logEvent(event)
                        // tryEmit, never emit: a suspending emit would stall polling if a
                        // consumer were slow, which is exactly the failure this guards.
                        if (!_events.tryEmit(event)) {
                            CanonLog.w("Event buffer full, dropped %s", EosEventCode.name(event.code))
                        }
                    }
                } catch (e: PtpException.TransactionMismatch) {
                    // P-02 already drained the endpoint. Count it and keep going - this is
                    // recoverable and dying here would be worse than the original problem.
                    consecutiveFailures++
                    CanonLog.w("Event poll hit a transaction mismatch (%d consecutive)", consecutiveFailures)
                } catch (e: Exception) {
                    consecutiveFailures++
                    CanonLog.w(e, "Event poll failed (%d consecutive)", consecutiveFailures)
                }

                if (consecutiveFailures >= config.maxConsecutiveFailures) {
                    CanonLog.e(
                        "Event loop wedged after %d consecutive failures - session needs re-initialising (O-06)",
                        consecutiveFailures,
                    )
                    _state.value = State.Wedged
                    return@launch
                }

                delay(config.pollIntervalMs)
            }
        }
    }

    private fun pollOnce(): List<EosEvent> {
        pollCount++
        val result = ptp.transact(CanonEosOperation.GET_EVENT)
        val payload = result.data ?: return emptyList()
        return EosEventParser.parse(payload)
    }

    /**
     * Keepalive.
     *
     * Sent unconditionally, not only when idle. The cost is one tiny transaction every ten
     * seconds; the cost of not sending it is the camera dropping the session mid-shoot.
     */
    private fun startKeepAlive() {
        keepAliveJob = scope.launch {
            while (isActive) {
                delay(config.keepAliveIntervalMs)
                try {
                    ptp.transact(CanonEosOperation.KEEP_DEVICE_ON)
                } catch (e: PtpException.OperationFailed) {
                    if (e.isUnsupported) {
                        // Not fatal - some bodies do not implement it. Stop trying rather
                        // than logging a failure every ten seconds forever.
                        CanonLog.w("KeepDeviceOn unsupported on this body; stopping keepalive")
                        return@launch
                    }
                    CanonLog.w(e, "Keepalive failed")
                } catch (e: Exception) {
                    CanonLog.w(e, "Keepalive failed")
                }
            }
        }
    }

    // --------------------------------------------------------------- ui lock

    /**
     * Locks the camera's own controls.
     *
     * Taken around property writes in M7 so the camera's dials cannot fight the app
     * mid-set. Failure is logged, not thrown - a UI lock we could not take is a degraded
     * experience, not a broken session.
     */
    fun setUiLock(locked: Boolean) {
        val op = if (locked) CanonEosOperation.SET_UI_LOCK else CanonEosOperation.RESET_UI_LOCK
        runCatching { ptp.transact(op) }
            .onFailure { CanonLog.w(it, "UI lock %s failed", if (locked) "set" else "reset") }
    }

    // --------------------------------------------------------------- shutdown

    /**
     * Stops polling and leaves remote mode.
     *
     * Order matters: stop polling first, then release remote mode. Releasing while the
     * loop is still running races a `GetEvent` against the mode change and can leave the
     * camera in a confused state that needs a power cycle.
     *
     * Never throws - this runs on teardown paths where the camera may already be gone.
     */
    fun stop() {
        if (_state.value == State.Stopped) return
        CanonLog.i(
            "Stopping EOS session after %d polls, %d events",
            pollCount,
            eventsReceived,
        )

        pollJob?.cancel()
        keepAliveJob?.cancel()
        pollJob = null
        keepAliveJob = null

        runCatching { ptp.transact(CanonEosOperation.SET_EVENT_MODE, 0) }
            .onFailure { CanonLog.d("SetEventMode(0) failed on shutdown (camera may be gone)") }
        runCatching { ptp.transact(CanonEosOperation.SET_REMOTE_MODE, 0) }
            .onFailure { CanonLog.d("SetRemoteMode(0) failed on shutdown (camera may be gone)") }

        _state.value = State.Stopped
    }

    /** Milliseconds since the last event, or -1 if none yet. Feeds the M11 watchdog. */
    fun millisSinceLastEvent(): Long =
        if (lastEventAtMillis == 0L) -1 else System.currentTimeMillis() - lastEventAtMillis

    private fun logEvent(event: EosEvent) {
        when (event) {
            is EosEvent.Unknown ->
                // Logged at warn with the raw bytes so an unanticipated event can be
                // decoded later from a committed log rather than being lost (M3 note).
                CanonLog.w("EOS event (undecoded): %s", event)

            is EosEvent.WillSoonShutdown ->
                CanonLog.e("Camera reports it will soon shut down - keepalive is not working (C-03)")

            is EosEvent.ObjectAdded ->
                CanonLog.i(
                    "EOS ObjectAdded: handle=0x%08X %s %d bytes",
                    event.objectHandle,
                    event.filename,
                    event.sizeBytes,
                )

            else -> CanonLog.d("EOS event: %s", event)
        }
    }
}
