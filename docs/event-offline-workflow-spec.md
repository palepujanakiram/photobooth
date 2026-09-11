# Event offline workflow — functional & technical spec

> **Companion to `docs/event-pipeline-plan-v2.md`.** That document owns the *storage and
> ingest mechanics* (SD probe results, dedupe, downscale, DB strategy) and its findings stand.
> This one owns the *workflow*: what the operator does, what the settings control, how the
> stages chain, and how frames are composited on-device.
>
> **Where this supersedes v2** is called out inline as **[supersedes v2]**. The largest one:
> v2 kept the new pipeline as a *parallel* workflow on its own route; this spec integrates it
> into the existing Event station picker instead.

---

## 1. Context

The event booth is a processing station, not a guest kiosk. A photographer shoots hundreds of
frames to SD cards; the booth imports them, an operator picks which ones proceed, and each
selected image runs a fixed chain — optional AI, optional frame, then print. With AI off the
whole thing must run with **no internet at all**.

Today `lib/screens/event_station/` has three roles (Capture, Theme, Print) that *look* like this
but are entirely server-brokered: each polls `EventStationApi.fetchBoard()`, and
`resolveEventPostSplashRoute` (`event_station_role.dart:39`) sends any station device to
`needsInternet` when WAN is down. Nothing about that path survives an offline event.

## 2. The workflow

```
  THREE IMAGE SOURCES
  ┌────────────────────┐
  │ SD card (station)  │
  │ Gallery picker     │──►┌──────────┐   ┌───────────┐   ┌──────────────────────────────┐
  │ Camera capture     │   │  Local   │──►│ Operator  │──►│      Processing chain        │
  └────────────────────┘   │  store   │   │ selection │   │  [AI?] → [Frame?] → [Print]  │
      all dedupe into      └──────────┘   └───────────┘   └──────────────────────────────┘
      the same ledger       downscaled     multi-select      steps fixed by settings,
                            derivative     + "Add to         frozen onto each item at
                                             queue" CTA       selection time
```

**All three sources feed one ledger.** SD card import (the new station), the gallery picker
(retained on the Capture station), and the camera itself all produce `evp_media_items` rows and
all pass through the same dedupe. The `IngestSource` interface is what makes them
interchangeable; only `listAll()` and `openRead()` differ.

### 2.1 Two entry paths, two different gates

The gate differs by source, because the situations differ:

| Source | Gate | Why |
|---|---|---|
| SD card | **Batch selection** — grid, multi-select, *Add to queue* | Hundreds of frames arrive at once; the operator triages. |
| Gallery picker | **Batch selection** — same screen | Same shape as a card import. |
| Camera capture | **Confirm button** on the capture screen → **auto-queue** | A guest is standing there. Waiting for someone to visit the import screen would strand them. |

Both paths freeze the step list identically — see §2.2. The only difference is *when* the freeze
happens: at *Add to queue* for batches, at *Confirm* for a live capture.

**Stage 1 — Import.** Explicit CTA. Auto-detect and auto-scan on card insert, but importing is a
deliberate tap. Dedupe and incremental sync exactly as specified in v2 §"The card diff".

**Stage 2 — Local store.** Downscaled print-ready derivative on device; **the original stays on
the card** (v2 §"Downscale on copy").

**Stage 3 — Operator selection.** The operator multi-selects imported images and taps
**"Add to queue"**. This is the only human gate.

**Stage 4 — Processing chain.** AI (if enabled) → frame (if enabled) → print. Steps come from
settings, uniformly, not per image.

### 2.2 Steps are frozen at selection time

**This is the key design decision** and it follows directly from "steps fixed by settings".

When the operator taps *Add to queue*, the enabled steps are resolved **once** and written onto
each item as an ordered list, e.g. `["ai","frame","print"]`. Workers then walk that list by index.

Why it must work this way: an event's settings *will* be changed mid-event (AI turned off because
the link died, auto-print paused because the ribbon ran out). If workers re-read live settings,
in-flight items change behaviour halfway through the chain and the operator cannot reason about
what any given photo will do. Freezing the plan per item makes each item's fate legible and
auditable, and makes a settings change apply cleanly to *subsequent* batches only.

## 3. Settings

### 3.1 Event offline mode is separate from kiosk offline mode

**[supersedes v2]** — v2 didn't distinguish these. There are now two unrelated flags and they must
never be conflated:

| Flag | Owner | Meaning | Consumed by |
|---|---|---|---|
| `KioskManager.isOperatingModeOffline()` | `/api/kiosk/by-code` | Guest kiosk runs without network payment/AI | Terms (`forceOffline`), staff dashboard |
| **`EventPipelineConfig.offlineMode`** (new) | `/api/event/by-code` + local override | Event pipeline runs with no WAN | Station routing, AI worker, mirror |

They are read from different endpoints, stored under different prefs keys, and surfaced in
different places. A kiosk in online mode can run an offline event and vice-versa.

### 3.2 Config resolution

Backend event flag → local override → default. **Null override = inherit**, mirroring
`KioskManager`'s existing idiom.

| Setting | Default | Effect |
|---|---|---|
| `pipelineEnabled` | off | Master switch. Shows the SD Import station; enables offline routing. |
| `offlineMode` | off | Event runs without WAN. Suppresses AI scheduling and mirror attempts. |
| `aiEnabled` | `photoMode != 'FRAME_ONLY'` | Adds `ai` to the step list. |
| `themeId` | event default | **The single look every AI job uses.** No per-image theme pick. |
| `frameEnabled` | `frameCount > 0` | Adds `frame` to the step list. |
| `frameId` | event default | Which frame to composite. |
| `scanFolders` | `["DCIM"]` | Folder prefixes an import scans. Operator can widen per card. |
| `autoPrint` | on | Adds `print` to the step list. Off = operator releases prints manually. |
| `defaultCopies` | 1 | |
| `printSize` | from kiosk | Drives both the print job and the compositing canvas. |
| `qualityFactor` | 1.0 | Downscale short-side multiplier (v2: base 1920). |
| `mirrorEnabled` | on | Upload derivatives + stages to backend. Forced off when `offlineMode`. |

Backend fields are read **if present** by a new parser in the new folder; `EventInfoModel` is not
edited (v2 constraint 4 holds).

### 3.3 Where the settings live

New **"Event pipeline"** section in **Kiosk settings** (the splash screen in `manageKiosk: true`
mode, `app_splash_screen.dart:849`). That is already where the kiosk and event codes are bound, and
it is already reachable from the station picker's back button via `_leaveToKioskSettings`.

The staff dashboard shows **live pipeline status read-only** (counts per stage, failed jobs,
disk headroom) and does not edit config, so there is one editable surface.

## 4. Station integration

**[supersedes v2]** — v2 said the existing station path stays "untouched — not migrated, not
mirrored, not re-routed". It is now integrated.

### 4.1 A fourth role

`EventStationRole` gains `sdImport = 'sd-import'`, with a matching route, picker card, and
`EventPostSplashRoute` case.

**Why a role and not a CTA inside Capture** — the two screens have opposite designs:

| | Capture station | SD import |
|---|---|---|
| State | Fire-and-forget, no local queue | Durable local ledger |
| Gate | None — shoot, upload, next guest | Operator selection |
| Navigation | Leaves to `/capture` and returns | Must stay put through a long import |

The Capture station's existing `_importItems` tray is already the awkward part of
`EventCaptureStationViewModel` for exactly this reason. And mechanically, an import in progress
would have to survive the `/capture` round trip.

**A "Import from card" shortcut** on the Capture station navigates to the import screen *without*
changing the persisted `stationRole`, so a single-operator event needs no role switching mid-event.

### 4.2 All existing screens stay — the flag changes what backs them

**[supersedes v2]** Nothing is deleted. Each screen keeps its layout and gains a local-pipeline
backing when `pipelineEnabled` is on.

| Screen | Flag **off** (today) | Flag **on** |
|---|---|---|
| **Capture** | Creates a server session, uploads, returns | Shoot → **Confirm** → registers an `evp_media_items` row and auto-queues it (§4B.3). **Gallery picker retained**, now feeding the batch selection grid rather than minting one session per photo. |
| **Theme** | Claims server theme jobs | Read-only status of items in the AI stage. Theme comes from `config.themeId`, so this is not a gate. |
| **Print** | Polls `fetchBoard()` | Drains `evp_pipeline_jobs(kind='print')`. |
| **SD Import** | — | New. Import → select → queue. |

With `pipelineEnabled == false` every screen behaves **byte-identically to today**. That is the
regression guard and it is an explicit test.

> **Open item:** with one event theme from settings, the Theme station has no decision left to
> make when the flag is on, so it is specified as a status surface. If you'd rather it stay a real
> gate — operator overrides the look on specific images and requeues them — say so; it's the
> "default theme, Theme station can override" variant and costs one extra job kind.

### 4.3 The picker becomes settings-driven

`event_station_picker_view.dart` currently hardcodes three `_StationChoice` widgets. It becomes a
list built from `enabledStationRoles(config)`:

- `sdImport` shown only when `pipelineEnabled`.
- `capture` / `theme` still shown when `offlineMode` — they now have local behaviour — but with a
  badge showing what is degraded.
- `print` always shown.

### 4.4 Per-role offline routing

`resolveEventPostSplashRoute` currently blanket-returns `needsInternet` for **any** role when
`wanAvailable == false`. It becomes per-role, and with the pipeline on, **no role needs WAN**:

```
requiresWan(role, config):
  if (config.pipelineEnabled) return false;   // every station has local behaviour
  return role != null;                        // else: today's blanket rule
```

`EventStationBoundShell` must render from **cached** event chrome when `hydrateBoundEvent`'s live
fetch fails, so an offline station shows its branding rather than an unstyled screen.

### 4.5 Status on every screen

All four screens carry the same **pipeline status strip**, fed from `evp_*` and needing no network:

```
  Imported 1,511 · Queued 412 · AI 38 · Framing 12 · Printing 4 · Done 1,045 · Failed 2
```

It reuses the existing `EventStationStatsBar` layout so the screens stay visually consistent, but
reads counts from the local ledger instead of `EventStationStats` from the board. Each screen also
highlights the stage it owns, and failed items are tappable through to a retry list.

## 4A. How an import works — scope and filtering

### 4A.1 Evidence from the real card

The probe card `1E6F-0961` contained:

```
DCIM/100CANON     ← 1,529 files, the actual photographs
CANONMSC          ← Canon thumbnails / metadata sidecars
MISC              ← Canon DPOF print-order files
Alarms  Android  Audiobooks  Documents  Download  Movies  Music
Notifications  Pictures  Podcasts  Recordings  Ringtones
System Volume Information
```

That card had been used in a phone. Scanning the whole volume would have swept in `Pictures/`,
`Download/` and ringtone artwork alongside the photographs. **This is why the default is
DCIM-only** — it is not a hypothetical concern, it is what was on the card.

### 4A.2 Scope

**Default: `DCIM/**`, recursing every subfolder.** Every camera writes there —
`100CANON`, `101CANON` after a 9,999-image rollover, `100MSDCF` (Sony), `100ND850` (Nikon),
`100_FUJI` (Fuji). The dedupe key already includes the full `relative_path`, so images with the
same filename in `100CANON` and `101CANON` never collide.

**The operator can widen it.** The review screen lists every folder found on the card with its
image count, DCIM subfolders pre-ticked:

```
  ☑ DCIM/100CANON ................ 1,511 images
  ☑ DCIM/101CANON ..................  212 images
  ☐ Pictures .......................... 47 images
  ☐ Download ........................... 8 images
```

So a photographer who dropped files outside DCIM is recoverable in one tap, without making the
common case dangerous. Ticks apply to that import only; `scanFolders` remains the default.

### 4A.3 There is no directory walk

With MediaStore this is one cursor over `content://media/{volumeName}/images/media`, filtered on
`relative_path`. The folder list and counts above come from `GROUP BY relative_path` over the same
query that already produces the dedupe key — no second pass, no `File.list()`, no per-file IPC.
The SAF fallback (if the Amlogic probe forces it) is the only path that needs real recursion.

### 4A.4 File types

**Import `image/jpeg`, `image/heic`/`image/heif`, `image/png`. Ignore RAW.**

RAW is excluded deliberately, not by oversight:

- In RAW+JPEG mode the camera writes `IMG_0631.CR3` beside `IMG_0631.JPG`. Both are the same
  photograph, so importing both would double every frame. Taking the JPEG is correct and needs no
  pair-matching logic.
- On-device RAW decode is slow and format-specific (`.CR2`/`.CR3`/`.ARW`/`.NEF`/`.RAF` all differ),
  and MediaStore's RAW indexing is inconsistent across vendors.
- RAW is never the only rendition on a booth card in practice; a photographer shooting RAW-only
  is not using an on-site print booth.

**If a card is RAW-only, the import reports "0 importable images" with the reason** rather than
silently finding nothing — otherwise it looks identical to a failed scan.

Junk is filtered for free: MediaStore does not index `CANONMSC` sidecars, `MISC` DPOF files, or
macOS `._IMG_*.JPG` AppleDouble stubs. That is the 1,529 → 1,511 gap measured on this card.

> **Unverified:** I don't know whether the probe card actually held any RAW files — the composition
> of the 18-file gap was inferred, not enumerated, and the device went offline before I could
> confirm. Worth one `ls` on the next card.

## 4B. Sessions, interventions, and the capture confirm

### 4B.1 One server session per photo, created by the mirror

**The host has accepted the event's terms**, so every photo auto-accepts on their behalf:
`acceptTermsAndCreateSession(kioskCode:, source:, groupConsentAccepted: true)` — exactly what
`_importOnePhoto` does today (`event_capture_station_viewmodel.dart:245`), with `source` varying by
origin: `event-sd-import`, `event-capture`, `event-gallery`.

**This needs WAN, so it is a mirror step, not an ingest step.** `evp_upload_queue.kind` becomes an
ordered three-stage chain per item:

```
  session  →  acceptTermsAndCreateSession   → writes remote_session_id
  asset    →  ingestKioskAsset              → uploads the derivative
  row      →  ingestKioskEntities           → mirrors stage changes
```

Offline, all three simply sit in the queue; when WAN returns they drain in order. **The AI step
blocks on `remote_session_id` being present** and re-queues with backoff until it is — that is the
ordering dependency, now with a concrete owner.

> **Throughput note:** a 3,000-frame event means 3,000 session creations. That is the same pattern
> as today's card import, but at 60× the volume. The mirror needs a request-rate cap and should
> create sessions in the background rather than in a burst. Worth measuring against a real backend
> before an event relies on it.

### 4B.2 Skip AI — the operator intervention

An AI-enabled event whose internet never works would otherwise strand every photo at `stage=AI`
forever. The queue screen therefore has selection and a **"Skip AI"** action:

1. Operator selects stuck items (or *select all*).
2. **Skip AI** rewrites `steps_json`, dropping `"ai"` and keeping `"frame"` when a frame is
   available, so the chain becomes `["frame","print"]` — or `["print"]` if not.
3. Any enqueued `ai` job is marked `CANCELLED`.
4. The item is marked **AI skipped** in the ledger and on screen, so the outcome is visible rather
   than looking like a normal completion.
5. `step_index` is recomputed; the next worker picks it up immediately.

This is the *only* sanctioned rewrite of a frozen step list. It stays consistent with §2.2 because
it is an explicit, logged operator action rather than settings drift leaking into in-flight work.

The same screen's selection also supports **skipping items entirely** (drop to `FAILED`/`SKIPPED`
without printing), for frames the operator decides against after seeing the AI result.

### 4B.3 Capture → Confirm → auto-queue

With the flag on, the Capture station's flow becomes:

```
  Capture next  →  [shoot]  →  CONFIRM screen  →  Confirm  →  auto-queue
                                     │                          (steps frozen here)
                                     └─ Retake ──► shoot again
```

On **Confirm**: the still is registered as an `evp_media_items` row *and* immediately queued with
the resolved step list — no visit to the selection grid. On **Retake**, nothing is written to the
ledger.

This is why `resolvePostCaptureRoute` needs care: today it returns straight to the Capture station
with `arguments: null` (`photo_capture_view_handlers.dart:126`), deliberately discarding the photo
because the server already has it. With the flag on there is no server yet, so the confirm step is
what replaces that upload as the commit point.

## 5. Data model

Extends v2's `evp_*` schema (same unversioned second connection to `kiosk.db`,
`CREATE TABLE IF NOT EXISTS`, no migration). Three additions:

```sql
-- [new] the per-item frozen plan
ALTER-equivalent: evp_media_items gains
  steps_json      TEXT,      -- '["ai","frame","print"]', frozen at selection
  step_index      INTEGER NOT NULL DEFAULT 0,
  selected_at_ms  INTEGER;   -- null = imported but not yet queued

-- [new] one row per rendition; print picks the best available
CREATE TABLE IF NOT EXISTS evp_media_renditions (
  media_id TEXT NOT NULL,
  kind TEXT NOT NULL,              -- 'source' | 'ai' | 'framed'
  path TEXT NOT NULL,              -- EventMediaStore relative path
  width INTEGER, height INTEGER, bytes INTEGER,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (media_id, kind));

-- [new] event frames cached as BYTES, not just metadata
CREATE TABLE IF NOT EXISTS evp_event_frames (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT NOT NULL, name TEXT,
  overlay_url TEXT NOT NULL,
  local_path TEXT,                 -- downloaded PNG in EventMediaStore
  width INTEGER, height INTEGER,
  downloaded_at_ms INTEGER);
CREATE INDEX IF NOT EXISTS evp_frames_event_idx ON evp_event_frames(event_id);
```

`pipeline_jobs.kind` gains `'frame'` alongside `'ai'` and `'print'`.

**Print input resolution:** `framed` → `ai` → `source`, first available wins. So a failed frame
step still prints the AI result, and an AI-off event prints the source derivative.

### 5.1 Stage values

`evp_media_items.stage`: `INGESTED` (imported, not selected) → `QUEUED` → `AI` → `FRAMING` →
`PRINTING` → `DONE`, plus `FAILED` and `PAUSED`. `stage` is derived from `steps_json[step_index]`;
it is stored denormalised so the console can group without recomputing.

## 6. The frame pipeline

**AI stays server-side. Framing is local.** This is what makes an AI-off event fully offline.

### 6.1 Fetch and cache

`getKioskFrames()` (`api_service.dart:593`) **already** accepts `eventCode` and already disk-caches
the frame *metadata* per kiosk+event. What is missing is the **overlay bytes**.

New `EventFrameCache`:
1. On event bind (and on operator demand), call `getKioskFrames()`.
2. For each frame, download `overlayUrl` and store the PNG in `EventMediaStore` under
   `event-frames/{eventId}/`.
3. Record in `evp_event_frames`, keyed by frame id.
4. Once cached, framing never touches the network again.

Frames must be fetched **while WAN is available**, i.e. during event setup. The SD Import station
shows an explicit **"Frames ready — 3 cached"** / **"Frames not downloaded"** indicator, because a
frame-enabled event that goes offline without cached frames cannot complete its chain. The station
refuses to start a frame-enabled batch when frames are missing, rather than failing 400 items one
at a time.

### 6.2 Compositing

New Kotlin `EventFrameCompositor.kt`, alongside `EventImageDownscaler.kt` in the same package and
on the same single-thread executor.

- Canvas = the configured `printSize` raster from `DnpPrintSize.kt` (e.g. 1920 × 1240 for 4×6).
- Photo drawn cover-fit, matching `DnpImageProcessor`'s existing behaviour so framed and unframed
  prints are composed identically.
- Frame PNG drawn over it with alpha, scaled to the canvas.
- Encode JPEG q88 → `evp_media_renditions(kind='framed')`.

**Why native rather than `package:image`:** `strip_compositor_local.dart` is the pure-Dart
precedent, but it works on a 1200×1800 strip sheet. A full-resolution decode + composite + encode
per image in pure Dart is on the order of seconds each on the Amlogic box; at 400 images that is the
difference between minutes and an hour. Same reasoning as the downscaler.

**Aspect mismatch:** if the frame PNG's aspect ratio differs from the target print size, it is
scaled to fit the canvas and centred rather than stretched. **Open question for the backend:**
whether ZenAI returns one frame per event or per print size. If one, a 4×6 frame used on 6×8 will
letterbox — worth confirming before build.

## 7. Offline semantics

| Condition | Behaviour |
|---|---|
| `offlineMode`, AI off | Full chain runs locally. Import → select → frame → print, no WAN. |
| `offlineMode`, AI on | AI jobs queue and wait; **"Skip AI"** (§4B.2) is the operator's way out. Warned at selection that AI cannot complete. |
| Session not yet created | AI blocks on `remote_session_id`, re-queues with backoff. Frame and print are unaffected. |
| Online, mirror on | Derivatives and stage rows upload best-effort via the v2 `EventMirrorWorker`. Never blocks the chain. |
| WAN drops mid-event | Local chain continues. AI jobs re-queue with backoff, not failure. Mirror pauses. |
| Frames not cached, frame enabled | Batch refused at selection with a clear message. |

## 8. UI

**SD Import station** — one screen, three states:

1. **Idle / no card** — "Insert a card", frame-cache status, counts from the local ledger.
2. **Scanning** — live "Scanning card… 254 photos found", *with an explicit still-scanning
   indicator*. Required: v2 measured a card mounting with **0 MediaStore rows**, reaching its full
   254 only ~11 s later. A premature read reports "0 new" on a full card.
3. **Review & select** — grid of imported images, "412 new · 1,088 already imported",
   select-all default, per-image toggles, and a **"Pick files manually…"** fallback. Footer shows
   the resolved chain — *"AI → Frame → Print · 1 copy"* — so the operator sees exactly what
   *Add to queue* will do before tapping.
4. **Safe to remove card.**

**Queue view** — counts per stage, failed items with retry, pause/resume.

## 9. Deferred

- **Guest status.** Per-image status via QR is deferred by decision. The hook exists
  (`createKioskShareLink`, `api_service.dart:65`, session-scoped with an optional `imageIndex`) and
  the mirror's `remote_session_id` mapping is what it will ride on — so nothing here blocks it later.
- Post-AI operator approval gate (selection is the only gate).
- Per-image step routing.
- Offline Capture and Theme stations — they stay server-only.
- CCAPI.

## 10. Build order

1. **Config + settings UI** — `EventPipelineConfig`, backend parse, Kiosk settings section.
   Nothing else can be tested without it.
2. **Ledger + queue + worker** — v2 Phase 0, plus `steps_json` / renditions.
3. **Ingest** — MediaStore source, dedupe, downscale, import CTA, selection UI.
4. **Frame** — cache + Kotlin compositor. Fully testable offline.
5. **Print** — local queue drain, consumables pause.
6. **AI** — server call, mirror ordering dependency.
7. **Station integration** — fourth role, settings-driven picker, per-role offline routing.
8. **Mirror** — `EventMirrorWorker`.

Steps 1–5 deliver a complete **offline, AI-off event** end to end. That is the shippable milestone;
6–8 add the online capabilities on top.

## 11. Verification

Beyond v2's list, this spec adds:

- **Frozen steps** — change settings mid-chain; in-flight items keep their original plan, the next
  batch picks up the new one.
- **Skip AI** — a stuck AI item rewrites to `frame→print`, its `ai` job is cancelled, and the
  result is marked *AI skipped* rather than silently completing.
- **Capture confirm** — Retake writes nothing to the ledger; Confirm writes exactly one row and
  queues it with the step list frozen at that moment.
- **Session ordering** — AI re-queues (never fails) while `remote_session_id` is null, and runs as
  soon as the mirror's `session` step lands.
- **Rendition fallback** — a failed frame step still prints the AI result; an AI-off event prints
  the source derivative.
- **Frame cache gate** — a frame-enabled batch is refused when frames are not cached.
- **Offline separation** — a kiosk in online mode runs an offline event, and vice-versa, with
  neither flag affecting the other.
- **Regression guard** — with `pipelineEnabled == false`, station routing and all three existing
  station screens behave exactly as today.
- **Aspect mismatch** — a 4×6 frame on a 6×8 print letterboxes rather than stretching.

## 12. Open questions

1. **Does the Theme station stay a status surface, or become an override gate?** (§4.2)
2. **Does ZenAI return one frame per event, or one per print size?** Affects §6.2 aspect handling.
3. **Print release when `autoPrint` is off** — does the operator release from the SD Import queue
   view, or from the Print station? Specified as the Print station.
4. **Does `config.themeId` need a fallback** when the named theme isn't in the event's cached
   catalogue — fail the AI step, or fall back to the first available theme?
5. Unchanged from v2: the Amlogic probe re-run, the derivative-only one-way door, and whether
   `/api/kiosk/ingest` accepts new entity types.

## 13. Decisions log

| Decision | Choice |
|---|---|
| Steps fixed per item | Frozen at selection time, not re-read live |
| AI location | Server-side; needs WAN |
| Frame location | On-device, native Kotlin compositor, after AI |
| Guest status | Deferred |
| Event offline flag | Backend event flag + local override; separate from kiosk offline |
| SD import placement | Fourth station role, plus a shortcut from Capture |
| Existing screens | All retained; flag switches what backs them |
| Gallery picker | Retained on Capture, re-pointed at the local ledger |
| Scan scope | `DCIM/**` default, operator can widen per card |
| File types | JPEG / HEIC / PNG; RAW ignored |
| Theme source | One event theme from settings; no per-image pick |
| Remote session | One per photo, auto-accepting terms on the host's behalf; created by the mirror |
| Stuck AI | Operator "Skip AI" rewrites steps to frame→print; only sanctioned step rewrite |
| Capture gate | Confirm button on the capture screen, then auto-queue — no selection grid |
