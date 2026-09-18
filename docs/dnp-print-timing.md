# DNP print timing

Why consecutive prints used to take ~35s each when the printer only needs ~13s, what
was actually wrong, and how to measure it again. Written so the next person does not
re-derive it from a silent log.

Measured 2026-09-18 on the 4 GB Amlogic RTC Mini PC (armeabi-v7a, Android 11) against a
DNP DS-RX1HS (FW DS-RX1 02.21), 4x6 / `s4x6`, debug build.

---

## The result

| | Before | After |
|---|---|---|
| Start latency, job sent → printer ACTIVE (stalled print) | 21.60s | **8.50s** |
| Start latency (non-stalled print) | 4.26s | 4.25s |
| Gap between consecutive prints, A done → B printing | **24.6s** | **11.20s** |
| Throughput, completion to completion | ~35s/print | **22.04s/print** |

Actual printing was never the problem: active → complete measured 13.0s on four of six
traced prints.

---

## Root cause

After a job stream is sent, `DnpPrintCompletionWaiter` polls `STATUS` once per second
until the printer reports active, then until it reports idle again. The **first** poll
after a job sent soon after a previous print never gets an answer — this printer drops
the STATUS command while it is still settling from the preceding job.

That alone would cost one second. It cost 17.4s because `DnpCommand.bulkReadWithRetry`
retried the **read** four times at a 4s timeout each:

```
4000 + (120 + 4000) + (240 + 4000) + (360 + 4000) = 16,720ms
```

Retrying the read cannot work here. The thing that failed is the *command*: no response
is in flight, so re-reading finds nothing however many times it asks. `clearInHalt()`
between attempts does not help either. What recovers it is sending a **fresh** command —
which only the caller's 1s poll loop does.

Traced, with `DnpTrace` enabled:

```
09-18 15:39:44.766  bulkRead attempt 0/4 len=8 timeout=4000ms took=4044ms: USB read failed at offset 0
09-18 15:39:49.120  bulkRead attempt 1/4 len=8 timeout=4000ms took=4231ms: USB read failed at offset 0
09-18 15:39:53.471  bulkRead attempt 2/4 len=8 timeout=4000ms took=4109ms: USB read failed at offset 0
09-18 15:39:58.078  bulkRead attempt 3/4 len=8 timeout=4000ms took=4245ms: USB read failed at offset 0
09-18 15:39:58.078  STATUS query failed: DnpPrinterException USB read failed at offset 0
09-18 15:39:58.079  poll 0: status=-1 read=17439ms sinceSend=17439ms active=false
09-18 15:39:59.162  poll 1: status=0  read=82ms    sinceSend=18522ms active=false   ← fresh command, 82ms
```

So 17.4s was spent on retries that could not succeed, delaying by exactly that long the
poll that could.

### The trigger is timing, not sequence

A job sent **2.7-3.0s** after the previous print completed stalls. One sent **3.2 minutes**
later does not:

| Job sent after previous completed | `poll 0` read |
|---|---|
| 3.2 min | 82ms (clean) |
| 2.96s | 17,439ms (before fix) |
| 2.70s | 4,331ms (after fix) |

Back-to-back is the normal case during an event, which is why this was constant in the
field and invisible in one-off testing.

### Why the delay mattered so much

`MIN_START_POLLS = 1` exists because the `CNTRL START` embedded in the job stream does
nothing on this printer — the standalone retry at poll 1 is what actually starts the job
(see the comment in `DnpPrintStatusHooks`). So a blind first poll does not merely waste
time, it postpones the command that starts printing.

---

## The change

`DnpCommand.queryResponse` — status polls only — now uses **one** read attempt:

- `readResponse` and `bulkReadWithRetry` take a `retries` parameter, defaulting to
  `READ_RETRIES = 4`, so real data transfers are unchanged.
- `queryResponse` passes `STATUS_POLL_READ_RETRIES = 1`.

The recovery path is not weakened. What actually recovers a dropped STATUS — a fresh
command, plus the `clearInHalt()` in `queryResponse`'s catch — still happens, 13s sooner.

---

## How to measure it again

`DnpTrace` (`android/app/src/main/kotlin/com/srisarani/fotozenai/dnp/DnpTrace.kt`) is
**debug-only**: it reads `FLAG_DEBUGGABLE` from the app context at channel registration,
so a release build cannot ship with it on. Release keeps the unconditional
`Print stage timings` and `Print completed` lines, which are enough for field triage.

Confirm it armed:

```
I/DnpTrace: DNP print tracing on (debuggable build)
```

Watch the milestones live:

```bash
adb logcat -v time | grep -E "job stream sent|printer went ACTIVE|Print completed|poll 0:|poll 1:|still idle|bulkRead attempt"
```

The numbers that matter:

- `poll 0: … read=Nms` — the decisive one. ~82ms is healthy, ~4,100ms is the stall
  costing one timeout, ~17,400ms means the multi-retry path is back.
- `printer went ACTIVE` — splits start latency from actual printing.
- `Print completed: waitForPrintComplete=Nms`.

To reproduce the stall, print two images back to back with AI disabled, so the second
job is sent within ~3s of the first completing. With AI enabled the ~35s generation
hides the effect entirely.

---

## Still open

**`STATUS_POLL_TIMEOUT_MS` 4000 → ~800ms.** Every healthy status read across six traced
prints measured 81-85ms, so 4000ms is ~48x the observed healthy read and 800ms still
leaves ~10x headroom. Would take the stalled print's start latency from ~8.5s to ~5s.

**Immediate re-send on a failed status read** instead of waiting the full 1s poll tick,
now that a fresh command is known to be the recovery. Changes the poll loop's shape
rather than a constant, so it wants its own measurement.

**Unexplained variance in active → complete.** Four prints measured 13.0s; two in one
back-to-back batch measured 17.3s and 10.8s. The pair still completed 22.04s apart, so
it averages out, and it is the printer's own cycle rather than app overhead — but two
samples are not enough to explain the spread. Worth pulling if print times feel erratic
during an event.

---

## Notes

The `7145792 bytes` in `Print stage timings` is **not** a file being re-read. It is the
dye-sublimation raster: `DnpPrintJobBuilder.buildJob` emits three full-resolution 8-bit
planes because the printer lays down yellow, magenta and cyan in separate passes.

```
1920 × 1240       = 2,380,800   one plane
            × 3   = 7,142,400   Y + M + C
      + headers   =     3,392   ESC/P + BMP, per plane
                  = 7,145,792
```

It is fixed by pixel dimensions, not by the stored JPEG's size — compressing the 1.5 MB
derivative harder would not change it by a byte. 1920 is the DS-RX1HS native width at
300 dpi (`DownscaleTarget.dnpNativeWidth`). At `send=~1200ms` it is ~5.9 MB/s over USB 2.0
and about 3% of a print, so it is not worth optimising.
