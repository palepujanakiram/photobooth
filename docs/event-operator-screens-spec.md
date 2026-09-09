# Event operator screens — spec

> Companion to `docs/event-offline-workflow-spec.md`, which owns the pipeline
> mechanics. This one owns **what the operator sees**: the screens, what each
> shows, and the states each can be in.
>
> **Status: for review.** No code written against this yet.

---

## 1. Why this replaces the station picker

The existing Event station screens are **role-based** — Capture, Theme, Print —
because each was a separate device talking to a server-brokered board. That was
the right shape for that design.

It is the wrong shape for this one. Three ingestion sources now feed **one local
queue** on **one device**, so "which role is this device" stops being the
question the operator is asking. What they actually need to know is: *is
everything ready, what is in the queue, and what is stuck.*

So the entry point becomes a **hub that shows state**, and the sources become
actions rather than roles.

### Coexistence

The existing event screens stay exactly as they are. This is a parallel flow,
reached only when `pipelineEnabled` is on. **Nothing is deleted until the new
flow has run a real event** — the server-brokered path remains the fallback if
something about the local pipeline disappoints on the day.

---

## 2. Constraints these screens are designed against

| Constraint | Consequence |
|---|---|
| **Touch only**, no D-pad | Normal tap targets; no focus-order design needed |
| **One device**, all three sources | No roles, no per-device state, no sync |
| **Operator/staff only** | No guest-facing copy, no consent flows, no idle attract state |
| **Amlogic box, low spec** | Paginated lists, pre-made thumbnails, no large decodes on scroll |
| **Offline is normal** | Every screen renders from the local ledger; nothing waits on a network call |

The performance constraint is the one that shapes the UI most, and §7 covers it
specifically.

---

## 3. Screen map

```
   Event bound + pipelineEnabled
              │
              ▼
      ┌──────────────┐
      │  EVENT HUB   │◄──────────────┐
      └──────┬───────┘               │
             │                       │
   ┌─────────┼─────────┬─────────────┤
   ▼         ▼         ▼             │
┌────────┐┌────────┐┌────────┐  ┌─────────┐
│ IMPORT ││CAPTURE ││ QUEUE  │  │SETTINGS │
└────────┘└────────┘└───┬────┘  └─────────┘
                        ▼
                  ┌──────────┐
                  │  DETAIL  │
                  └──────────┘
```

Five screens plus one detail view. Every one returns to the hub.

---

## 4. Screen 1 — Event hub

The screen an operator can leave open all night. Lands here on entering an event.

```
┌────────────────────────────────────────────────┐
│  ‹   Priya & Arjun                        ⚙    │
│      WARM PEACH TO PURPLE                      │
├────────────────────────────────────────────────┤
│  READY TO RUN                                  │
│  ✓ Camera    Canon EOS R · PTP                 │
│  ✓ Printer   DS-RX1 · 4x6 · ~380 prints        │
│  ✓ Frames    1 cached                          │
│  — AI        off for this event                │
│  ✓ Storage   46 GB free                        │
├────────────────────────────────────────────────┤
│     12          3           148         0      │
│   QUEUED     WORKING       DONE      FAILED    │
├────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐    │
│  │ Import from card │  │     Capture      │    │
│  └──────────────────┘  └──────────────────┘    │
│  ┌────────────────────────────────────────┐    │
│  │            Open queue                  │    │
│  └────────────────────────────────────────┘    │
└────────────────────────────────────────────────┘
```

### The readiness block is the point of this screen

Events go wrong in a specific way: **something was not ready, and nobody found
out until a hundred photos in.** No frame cached and the link has since gone.
Printer out of media. Camera asleep. Disk nearly full.

Each of those is trivially detectable *before* it matters, and invisible
afterwards. Putting them on the landing screen converts a mid-event disaster into
a glance during setup.

| Row | Green | Amber | Red |
|---|---|---|---|
| Camera | Connected, model named | — | Not connected — Capture disabled |
| Printer | Connected, size, prints left | Media low | Not connected, or **paused: ribbon/paper** |
| Frames | All cached | Some cached | **Frame on but artwork missing** — framing cannot run offline |
| AI | On, theme named | On, **no theme set** — AI will be skipped | On, offline — jobs will wait |
| Storage | Free space | Below 4 GB | Below 1 GB — import blocked |

An amber or red row is **tappable** and explains what to do. "Frames not cached"
is the one that most needs this: it is silent until an event goes offline, and
then every single item defers.

### Counters

Four numbers, tapping any one opens the queue **filtered to it**. `FAILED` is red
when non-zero and never hidden.

### Actions

- **Import from card** — disabled with "Insert a card" when no volume is mounted
- **Capture** — disabled when no camera is connected
- **Open queue** — always available

---

## 5. Screen 2 — Import from card

Largely as built and verified on device.

**States:** no card · scanning · review · importing · safe to remove · card not
readable · card empty · only RAW · nothing new · needs photo permission.

```
┌────────────────────────────────────────────────┐
│  ‹   Import from card                          │
├────────────────────────────────────────────────┤
│  412 new · 1,088 already imported              │
│  18 RAW files skipped                          │
│                                                │
│  ☑ DCIM/100CANON 1,511   ☐ Pictures 47         │
├────────────────────────────────────────────────┤
│  [thumb] IMG_8344.JPG   6.9 MB            ☑    │
│  [thumb] IMG_8345.JPG   6.6 MB            ☑    │
│  ...                                           │
├────────────────────────────────────────────────┤
│  AI → Frame → Print 4x6 · 1 copy               │
│  [All] [None]                    [ Import 412 ]│
└────────────────────────────────────────────────┘
```

**Change from today:** the list gains thumbnails. It currently shows names only,
because at import time no derivative exists yet and decoding hundreds of 7 MB
originals to draw a grid is exactly the memory mistake the old tray made. §7
resolves this — the source thumbnail is generated during the scan pass, not by
decoding the original per tile.

The footer chain preview stays. It is the last moment before steps are frozen
onto each item, so it should say plainly what is about to happen.

---

## 6. Screen 3 — Capture

Tethered EDSDK or Direct PTP. CCAPI plugs in here later without changing the
screen.

```
┌────────────────────────────────────────────────┐
│  ‹   Capture                    Canon EOS R ✓  │
├────────────────────────────────────────────────┤
│                                                │
│              [ live view or                    │
│                last frame ]                    │
│                                                │
├────────────────────────────────────────────────┤
│  Recent:  [t] [t] [t] [t] [t]                  │
├────────────────────────────────────────────────┤
│            (  ●  Shutter  )                    │
└────────────────────────────────────────────────┘

after a shot ─────────────────────────────────────
│         [ the captured frame ]                 │
│   [ Retake ]              [ Confirm ]          │
```

**Confirm is the commit point.** It registers the item and queues it with the
steps frozen at that moment. Retake writes nothing at all.

The **recent strip** matters more than it looks: the photographer needs to see
frames landing to trust the thing is working. Without it, a silent failure looks
identical to a working booth until the queue is checked.

---

## 7. Screen 4 — Queue

The operator's working view, and the screen most at risk of making a weak box
feel stuck.

```
┌────────────────────────────────────────────────┐
│  ‹   Photo queue                               │
├────────────────────────────────────────────────┤
│  Queued 12 · Framing 3 · Done 148 · Failed 2   │
│  ⏸ Print queue paused — check ribbon           │
├────────────────────────────────────────────────┤
│  [All 165] [Queued 12] [Framing 3] [Done 148]  │
│  [Failed 2]                                    │
├────────────────────────────────────────────────┤
│   ┌────┐  ┌────┐  ┌────┐                       │
│   │ ▨  │  │ ▨  │  │ ▨  │                       │
│   └────┘  └────┘  └────┘                       │
│   IMG_44   IMG_45   IMG_46                     │
│   Failed   Framing  Done                       │
│   ...                          [ Load more ]   │
├────────────────────────────────────────────────┤
│  [Run local now]  [Retry 2 failed]  [Skip AI]  │
└────────────────────────────────────────────────┘
```

### Performance rules, not preferences

These are the difference between smooth and unusable on the Amlogic box:

1. **A dedicated thumbnail rendition**, ~320 px short side, ~30 KB. Roughly 20×
   less to read than the 2880 px derivative, and a trivial decode.
2. **Generated from the decode that already happened.** The downscaler holds the
   full bitmap; the compositor holds the finished canvas. Each emits two encodes
   from one decode, so a thumbnail costs a few milliseconds and **no extra read**.
3. **Overwritten as stages complete**, so the grid always shows current state —
   the operator sees the framed result, not the raw import.
4. **Paginated**, ~60 per page, load-more on scroll. Pagination bounds how many
   are live; thumbnails bound what each costs. Both, not either.

Disk cost is roughly 30 KB × 3,000 ≈ 90 MB against ~4 GB of derivatives.

### Action naming

`Run now` currently drains **only** the local stages — AI and the mirror are
excluded deliberately, since either can block for a long time. The label
overstates it: on an AI event an operator would press it, see nothing happen to
items sitting at AI, and reasonably conclude it is broken. Rename to **Run local
now**, or kick AI and the mirror without awaiting them.

---

## 8. Screen 5 — Item detail

Reached by tapping any tile. **This is the screen that does not exist today**, and
its absence is a real gap: an operator can currently see *that* something failed
but not *why*, which is not enough to act on.

```
┌────────────────────────────────────────────────┐
│  ‹   IMG_8344.JPG                              │
├────────────────────────────────────────────────┤
│   Source        AI          Framed             │
│   ┌──────┐   ┌──────┐    ┌──────┐              │
│   │  ▨   │   │  ▨   │    │  ▨   │              │
│   └──────┘   └──────┘    └──────┘              │
│   2880×1920  2880×1920   1240×1920             │
├────────────────────────────────────────────────┤
│  Stage    Failed at Print                      │
│  Chain    AI → Frame → Print                   │
│  Error    Ribbon end — replace ribbon          │
│  Source   SD card 2609-0353 · DCIM/100CANON    │
│  Shot     9 Sep 2026, 03:39                    │
├────────────────────────────────────────────────┤
│  [ Retry ] [ Skip AI ] [ Reprint ] [ Remove ]  │
└────────────────────────────────────────────────┘
```

Showing all three renditions side by side is how an operator answers "did the
frame come out right" without going to the printer. **Error is the real error
text**, not a category.

---

## 9. Screen 6 — Event settings

Currently buried in Kiosk settings, which is the wrong place: it is event
configuration, and the operator reaches for it from the event.

Same controls as the existing panel — AI + theme, frame + which, print size,
copies, auto-print, scan folders — plus the **resolved chain preview**, and one
addition: a **frame cache status with a Download now action**, so an operator can
fix the "frames not cached" warning from the hub without guessing how.

---

## 10. What is deliberately not here

- **Guest-facing screens.** Operator/staff only for this phase.
- **CCAPI.** The third ingestion source plugs into Capture later; nothing about
  these screens changes when it does.
- **Multi-device queue.** Separate document. Worth noting the venue network is
  slow, so a cloud-brokered board is not the answer — devices on the same LAN
  finding each other directly is the direction to explore.
- **Deleting the existing event screens.** Not until the new flow has run a real
  event.

---

## 11. Open questions

1. **Does the hub replace the station picker outright** when `pipelineEnabled` is
   on, or sit alongside it as a fifth choice? Replacing is cleaner; sitting
   alongside is safer while both flows exist.
2. **Should Capture auto-queue, or land in the queue as `INGESTED` for review?**
   Spec §4B.3 says auto-queue because a guest is waiting. Worth confirming now
   that the same device also runs the queue.
3. **Reprint semantics** — does Reprint re-run the print step on the existing
   framed rendition, or re-run the whole chain? The former is almost certainly
   what an operator means.
4. **Does the readiness block need a printer media count?** It requires a DNP
   status query the driver already supports, but the count's accuracy across
   media types has not been verified.
