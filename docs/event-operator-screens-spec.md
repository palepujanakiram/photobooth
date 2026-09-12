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

The hub **replaces the station picker** when `pipelineEnabled` is on — the two
entry points would otherwise compete and an operator would have to know which one
their event uses.

But **no existing screen or code is removed.** Capture, Theme and Print stay
exactly as they are, reachable when the flag is off, and remain the fallback if
something about the local pipeline disappoints on the day. Deletion is a decision
to take after the new flow has run a real event, not before.

---

## 2. Constraints these screens are designed against

| Constraint | Consequence |
|---|---|
| **Touch only**, no D-pad | Normal tap targets; no focus-order design needed |
| **One device**, all three sources | No roles, no per-device state, no sync |
| **Operator/staff only** | No guest-facing copy, no consent flows, no idle attract state |
| **Amlogic box, low spec** | Paginated lists, pre-made thumbnails, no large decodes on scroll |
| **Offline is normal** | Every screen renders from the local ledger; nothing waits on a network call |
| **ZenAI is the source of event config** | Settings, banners and frames are fetched **once per event**, cached, and used for the rest of it |

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

## 3A. Entering an event

Event code entered on the bind screen → **straight to the hub**. The hub renders
immediately and fills in as the sync lands.

```
  bind screen        hub (0s)              hub (2s)
  ┌──────────┐      ┌──────────────┐      ┌──────────────┐
  │ GALA-01  │  →   │ Syncing…     │  →   │ READY TO RUN │
  │ [Enter]  │      │ ⟳ event      │      │ ✓ Camera     │
  └──────────┘      │ ⟳ frames     │      │ ✓ Frames  1  │
                    └──────────────┘      └──────────────┘
```

**Not a blocking fetch before the hub appears.** A slow venue link would leave
the operator on a spinner with nothing to look at, and a failed fetch needs a
screen to report itself on anyway. The readiness block already exists to say
"this part is not ready yet" — the first sync is simply another row in it.

### Nothing is imported before settings arrive

**Import and Capture are both disabled until the event has synced at least
once**, with the reason on the button rather than a silent grey-out:

```
┌──────────────────┐
│ Import from card │   Waiting for event settings
└──────────────────┘
```

Photos taken in before settings exist would have **no chain frozen onto them** —
no way to know whether they should be styled, framed or printed. They would sit
at `INGESTED` indefinitely, and the operator would have imported four hundred
photographs that do nothing.

Blocking is the honest behaviour: the card is not going anywhere, and a sync is
seconds once there is signal. It also removes a whole class of "why is nothing
happening" support question.

If the sync fails and **nothing is cached**, the hub says so plainly and offers
Retry — with import still blocked. If a **previous cache exists**, the event runs
on it and the row reads "Using settings from 8 Sep".

---

## 4. Screen 1 — Event hub

The screen an operator can leave open all night. Lands here on entering an event.

```
┌────────────────────────────────────────────────┐
│  ‹   Priya & Arjun                        ⚙    │
│      WARM PEACH TO PURPLE                      │
├────────────────────────────────────────────────┤
│  READY TO RUN                    synced 09:12  │
│  ✓ Camera    Canon EOS R · PTP                 │
│  ✓ Printer   DS-RX1 · 4x6                      │
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

The hub stays a **state** screen — readiness, counts, three ways out. Which cards
happen to be seated is detail that belongs with the job of importing, not on the
landing screen, and it would otherwise grow and shrink under the counters every
time someone touched the reader.

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
| Printer | Connected, print size | — | Not connected, or **paused: ribbon/paper** |
| Frames | All cached | Some cached | **Frame on but artwork missing** — framing cannot run offline |
| AI | On, theme named | On, **no theme set** — AI will be skipped | On, offline — jobs will wait |
| Storage | Free space | Below 4 GB | Below 1 GB — import blocked |

An amber or red row is **tappable** and explains what to do. "Frames not cached"
is the one that most needs this: it is silent until an event goes offline, and
then every single item defers.

### Counters

Four numbers, tapping any one opens the queue **filtered to it**. `FAILED` is red
when non-zero and never hidden.

`synced 09:12` is when event config last came from ZenAI, with a tap to re-sync.
An operator who changed something on the backend needs to know whether this
device has it yet.

### Actions

- **A card row** — opens Import for that specific volume
- **Capture** — disabled when no camera is connected
- **Open queue** — always available

---

## 5. Screen 2 — Import from card

Largely as built and verified on device.

**States:** pick a volume · scanning · review · importing · safe to remove ·
card not readable · card empty · only RAW · nothing new · needs photo permission.

### Step 1 — pick a volume

```
┌────────────────────────────────────────────────┐
│  ‹   Import from card                          │
├────────────────────────────────────────────────┤
│  Choose a card to scan                         │
│                                                │
│  ┌────────────────────────────────────────┐    │
│  │ ▸ SD card  2609-0353         119 GB    │    │
│  ├────────────────────────────────────────┤    │
│  │ ▸ SD card  1E6F-0961          64 GB    │    │
│  └────────────────────────────────────────┘    │
│                                                │
│  Nothing is read until you choose a card.      │
└────────────────────────────────────────────────┘
```

A multi-slot reader can hold several cards at once, so "the card" is not
something the app can assume. Every mounted volume is listed, and **nothing is
read until the operator taps one**.

Not auto-scanning matters beyond the ambiguity: a scan burns I/O on a card the
operator did not mean, and on a slow box it competes with whatever the queue is
already doing. The explicit tap also gives a natural moment to show *which* card
is being read, which matters when two are seated.

With one card the list still appears — a single row, one tap. Consistency beats
saving a tap, and it keeps the "which card am I looking at" answer on screen.

Removing a card removes its row; removing the one being scanned is §9A. No cards
at all shows "Insert a card in the reader".

### Step 2 — scan and select

```
┌────────────────────────────────────────────────┐
│  ‹   SD card 2609-0353                         │
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
│  [Failed 2]                          [ Select ]│
├────────────────────────────────────────────────┤
│   ┌────┐  ┌────┐  ┌────┐                       │
│   │ ▨  │  │ ▨  │  │ ▨  │                       │
│   └────┘  └────┘  └────┘                       │
│   IMG_44   IMG_45   IMG_46                     │
│   Failed   Framing  Done                       │
│   ...                          [ Load more ]   │
└────────────────────────────────────────────────┘

selection mode ───────────────────────────────────
│  3 selected            [ All ] [ None ] [ ✕ ]  │
│   ┌────┐  ┌────┐  ┌────┐                       │
│   │ ▨ ☑│  │ ▨ ☑│  │ ▨ ☐│                       │
│   └────┘  └────┘  └────┘                       │
├────────────────────────────────────────────────┤
│  [ Retry ] [ Skip AI ] [ Reprint ] [ Remove ]  │
└────────────────────────────────────────────────┘
```

### Nothing acts on everything

Actions apply **only to what the operator selected**. A bare `Retry all` is the
kind of button that quietly reprints eighty photos when someone meant three, and
on dye-sub media that is real consumable spent for nothing.

So: tap **Select**, tick items, then act. `All` and `None` are there for the case
where the whole filter genuinely is the target — filter to `Failed`, tap `All`,
`Retry` — which keeps the bulk case to three taps without making it the default.

An action only appears when it is valid for the selection: `Skip AI` when
something selected sits at AI, `Reprint` when something has finished.

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

### Replacing "Run now" rather than renaming it

`Run now` is the wrong control, and renaming it to `Run local now` only makes the
name accurate — it does not make it useful.

The queue already runs continuously: frame and print tick every three seconds. A
`Run now` button implies the opposite, that work waits for a human. It also lied
about scope, draining only the local stages while items sat at AI.

**What an operator actually needs is the reverse — a way to stop.** Ribbon change,
paper reload, moving the printer: all want processing held and then resumed. So:

```
│  ● Processing — 12 queued            [ Pause ] │
│  ⏸ Paused                            [ Resume ]│
```

A live indicator that the queue is working, and one control to hold it. `Pause`
suspends every stage, survives a restart (it is queue state, not screen state),
and the hub shows it too so a paused queue is never a mystery.

The diagnostic case `Run now` half-served — "is this thing stuck?" — is answered
better by the indicator itself: if it says Processing and the counts do not move,
that is a real fault worth surfacing, not something to paper over with a button.

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

**Reprint prints another copy of whatever the finished output is** — the framed
version if there is one, else the AI result, else the imported photo. It does not
re-run AI or framing: the operator wants another print of what they can see, not
a fresh generation that might come out different.

---

## 9. Screen 6 — Event settings

Currently buried in Kiosk settings, which is the wrong place: it is event
configuration, and the operator reaches for it from the event.

### Read-only. ZenAI is the only source

Event settings, banners and frames are configured on the backend. The device
**syncs once when the event is bound** and uses that for the rest of the event,
so nothing on any screen waits on a request and a venue with no usable link still
runs correctly.

**There are no local overrides.** One source of truth means a device can never
silently disagree with the backend, and an operator can never "fix" an event into
a state nobody can reproduce. The screen is a readable record of what this device
is running, plus `Sync`.

The practical consequence: getting an event wrong is fixed on ZenAI and re-synced,
not worked around on the box. That is the right place for it to be fixed, but it
does mean a badly configured event is blocked on backend access — worth knowing
before a venue with no signal.

> **During development** these values are hardcoded on the device so the flow can
> be exercised before the backend carries them. That scaffold comes out once
> `/api/event/by-code` returns the real fields.

```
┌────────────────────────────────────────────────┐
│  ‹   Event settings              (read only)   │
│      Synced from ZenAI · 9 Sep 09:12  [Sync]   │
├────────────────────────────────────────────────┤
│  AI generation                              on │
│  Restyles each photo before framing.           │
│  Theme · Warm Peach                            │
│                                                │
│  Apply frame                                on │
│  Adds the event's border to the finished       │
│  photo. Downloaded once, then works offline.   │
│  Frame · Feriya y Fiesta   ✓ cached            │
│                                                │
│  Auto print                                 on │
│  Prints each photo as soon as it is ready.     │
│  Off means you release prints yourself.        │
│                                                │
│  Copies per photo                            1 │
│  How many prints of each finished photo.       │
│                                                │
│  Print size                                4x6 │
│  Must match the media loaded in the printer.   │
├────────────────────────────────────────────────┤
│  Each photo will run                           │
│  AI → Frame → Print 4x6 · 1 copy               │
└────────────────────────────────────────────────┘
```

**Every setting carries one line saying what it does.** These are read by an
operator under time pressure who did not configure the event, and a bare toggle
labelled "Apply frame" does not tell them that turning it off means the prints
come out plain.

`Sync` re-fetches on demand, for when something changed on the backend
mid-event. It is the only control on the screen. The timestamp is the same one
shown on the hub.

The frame row doubles as the fix for the hub's "frames not cached" warning: it
shows cache state and downloads on demand.

---

## 9A. Card removed mid-import

An operator will pull a card early — misreading progress, needing the card back,
or simply knocking the reader. This has to be safe, because the current
behaviour loses photographs.

### The failure as it stands

`_importOne` inserts the ledger row **first**, then writes the derivative. When
the volume disappears, every remaining photo goes:

```
insertIfNew       → row created      ✓
_storeDerivative  → source gone      ✗
                  → row marked FAILED
```

And the tier-1 dedupe (`knownSourceRefs`) matches on **every row regardless of
stage**. So:

1. Card pulled at photo 50 of 400
2. Photos 51–400 each get a FAILED row with no image behind it
3. Operator reinserts and rescans → **"0 new · 400 already imported"**
4. Those 350 photographs are now invisible to import, and Retry cannot help —
   there is no derivative to work from and ingest is not a queue job

**350 photos lost, while the screen reports success.** For a product whose entire
promise is "hand the card back safely", that is the worst failure available.

### The fix: roll back, do not fail

Distinguish **"the source went away"** from **"this photo is bad"**.

- Source gone → **delete the ledger row.** The photo returns to unknown, so a
  rescan finds it as new and the operator simply continues.
- A photo that genuinely will not decode → **FAILED**, as now. That is a real
  fault and deserves to stay visible.

Only the second is a failure. Recording the first as one is what converts a
recoverable interruption into silent loss.

### Stopping cleanly

`IngestWorker.import()` already takes a `shouldContinue` hook, checked before
each photo. Wiring the card-detect unmount stream into it turns 350 individual
failures into one clean stop, with the report carrying
`stoppedEarly: true, stopReason: 'Card removed'`.

A per-item volume check is available as a belt-and-braces addition if the
broadcast ever proves unreliable, at a few milliseconds per photo.

### What the operator sees

```
┌────────────────────────────────────────────────┐
│                    ⚠                           │
│              Card removed                      │
│                                                │
│   Imported 50 of 400. The rest are still on    │
│   the card — reinsert it and scan again to     │
│   continue.                                    │
│                                                │
│                 [ Done ]                       │
└────────────────────────────────────────────────┘
```

One honest message rather than a wall of failures. It is **truthful only because
of the rollback** — without it, "scan again to continue" would be a lie, since
the rescan would report nothing new.

Resuming costs nothing: the 50 already imported dedupe away on the next scan.

---

## 9B. Everything is scoped to one event

Every screen shows **only the bound event's photos**. The queue, the counters,
the hub totals and the item detail all filter on `event_id`.

This matters more than it sounds. The ledger is durable across events, so
without scoping an operator opening the queue at a wedding would see last
weekend's corporate party mixed in — counts wrong, "Retry all failed" reaching
into a finished event, and a real chance of reprinting the wrong couple's photos.

Concretely:

- `evp_media_items.event_id` is already recorded at import; every read filters on
  the currently bound event
- Items with a **null** `event_id` (imported before an event was bound) are shown
  only under an explicit "Unassigned" filter, never mixed into an event's counts
- Dedupe stays **global**, not per-event. The tier-1 and content keys are about
  *this photograph*, and re-importing the same card into a second event should
  still be recognised — the operator is told it is already imported rather than
  silently duplicating it

## 9C. Pre-event and post-event activities

Two phases exist around the event that this spec has so far ignored, and both
need their own design pass.

**Pre-event** — everything that must be true before guests arrive: event bound
and synced, frames downloaded, printer loaded and reachable, camera connected,
enough free storage. The hub's readiness block is the beginning of this, but a
deliberate "set up this event" flow that walks an operator through it would catch
more than a passive panel.

**Post-event** — the event is finished and the device has to be handed on:

- Confirm nothing is unprinted or failed
- Ensure everything has mirrored, if it is going to
- **Clear the local database and images**: the event's `evp_media_items`,
  renditions, jobs, cached settings, banners and frames
- Leave the device clean for the next event

The cleanup is the part with teeth. A 3,000-frame event is roughly 4 GB of
derivatives, and without a purge a box does three events and fills its disk.
Equally it must not run while anything is unprinted or unmirrored, or it destroys
work — so it belongs behind an explicit, checked operator action, not a timer.

> **Planned, not specified.** Both phases get their own pass once the core
> workflow is stable. Noted here so the data model keeps them possible:
> `event_id` on every row is what makes a per-event purge a single delete rather
> than an archaeology exercise.

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

## 11. Decisions taken

| Question | Answer |
|---|---|
| Hub vs station picker | Hub **replaces** the picker when the flag is on |
| Remove the old screens? | **No** — keep the code and screens; revisit after a real event |
| Capture destination | Confirm queues into the **same** queue as card imports |
| Reprint | Another copy of the **finished output**, whatever stage produced it |
| Printer media count | **Later**, once the flow is stable |
| Card scanning | **Never automatic** — the operator taps a specific volume |
| Queue actions | **Selection only**, never a bare act-on-everything |
| Event config | **ZenAI is the source**, synced once per event and cached |
| Local overrides | **None.** Settings are read-only; fix the event on ZenAI and re-sync |
| Entry flow | Event code → **hub immediately**, sync reported on the readiness block |
| Card pulled mid-import | **Roll the row back**, stop cleanly, tell the operator to reinsert |
| Photo scoping | Every screen filters on `event_id`; dedupe stays global |
| Pre/post event | Acknowledged, designed later; per-event purge kept possible |
| Card list location | **Inside Import**, not on the hub; hub keeps an Import button |
| Import before sync | **Blocked** — no photo enters without a chain to run |
| Misconfigured event | **No escape.** Fixed on ZenAI and re-synced; revisit later |

## 12. Backend: what exists today, and what is missing

Read from `EventInfoModel` and the cached response for `GALA-01`.

### `GET /api/event/by-code/:code` returns today

| Field | Type | Used for |
|---|---|---|
| `id` | string | **Event scoping** — the key everything filters on |
| `code` | string | Bind and cache key |
| `name` | string | Hub title |
| `photoMode` | `BOTH` / `FRAME_ONLY` / … | Currently the only signal for whether AI applies |
| `currentlyActive` | bool | Whether the event is live |
| `themeCount`, `themeIds` | int, string[] | Catalogue size and ids |
| `frameCount`, `frameIds` | int, string[] | Catalogue size and ids |
| `outputMode` | string | Output shape |
| `description` / `tagline` | string | Hub subtitle |
| `skin` | `{ id, name, subtitle, bannerFrom, bannerTo, ink }` | Banner gradient and ink — **the banner already arrives** |

Frame **artwork** comes separately from `GET /api/kiosk/frames`, which already
accepts an `eventCode` and returns `{ id, name, overlayUrl }`. That is enough to
download and cache overlays, and is already working.

### Missing — needed for read-only settings

Without these the device cannot know how to run an event, and today falls back to
hardcoded values.

| Field | Type | Default if absent | Why it is needed |
|---|---|---|---|
| `aiEnabled` | bool | `photoMode != 'FRAME_ONLY'` | Whether AI is in the chain. `photoMode` is a poor proxy — it describes output, not whether to generate |
| `themeId` | string | — | **Which** look every AI job runs under. `themeIds` gives a list with no indication which one the event uses; without it AI is dropped from the chain entirely |
| `frameEnabled` | bool | `frameCount > 0` | Whether framing is in the chain |
| `frameId` | string | — | **Which** frame. Same problem as `themeId`: a list of ids is not a choice |
| `autoPrint` | bool | `printerEnabled` | Print automatically, or hold for operator release |
| `defaultCopies` | int | `1` | Prints per photo |
| `printSize` | `s4x6` / `s5x7` / `s6x8` / `s2x6` | kiosk default | Must match loaded media; also drives the compositing canvas |

**The two that matter most are `themeId` and `frameId`.** Everything else has a
sane default, but "here are five frame ids" does not tell the device which one to
composite, and an event with several configured currently has no way to say.

### Nice to have, not blocking

| Field | Why |
|---|---|
| `pipelineEnabled` | Lets the backend turn the local pipeline on per event instead of per device |
| `offlineMode` | Declares an event as offline up front rather than inferring it |
| `qualityFactor` | Tune the derivative size for an event that wants larger prints |
| `startsAt` / `endsAt` | Pre-event and post-event flows (§9C) need to know when an event is over |

`startsAt` / `endsAt` are worth including early even though nothing uses them
yet — post-event cleanup is much safer when the device knows the event has ended
rather than relying on an operator to say so.

---

## 13. Still open

Nothing blocking. Both previous questions are closed:

- **On-site escape for a misconfigured event** — none, deliberately. Fixed on
  ZenAI and re-synced. Revisit if a real event gets stuck behind it.
- **Re-queueing `INGESTED` photos** — cannot arise. Blocking import before sync
  means no photo ever enters without a chain, so there is nothing to re-queue.

The remaining unknown is not a design question but a dependency: **`themeId` and
`frameId` (§12) must exist on the backend** before an AI or frame event can run
on real config rather than hardcoded values.
