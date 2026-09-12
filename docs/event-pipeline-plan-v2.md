# Event pipeline v2: Ingest → AI → Print, offline-capable

> **Supersedes `docs/event-pipeline-plan.md`.** That draft's architecture survives; its DB
> strategy, storage strategy, dedupe key and mirror strategy do not. Changes are marked
> **[v2]** throughout, with the reasoning kept inline so the decisions can be re-litigated
> later on their merits rather than re-derived.
>
> **Status: ready to build. The storage probe has been run — on a phone, not the box.**
> The mechanism is now **MediaStore**, not SAF and not plain `File`; see
> [Probe results](#probe-results-2026-09-07). That result is measured, but it was measured on a
> OnePlus Nord CE (Android 13, API 33), **not** on the Amlogic box, so it must be re-run there
> before we commit. Everything else is settled.

## Context

Today the app is a **guest-facing kiosk**: one guest, one session, one photo, captured and
processed and printed synchronously while they stand there. The event use case is different — a
photographer shoots hundreds of frames, and the booth is a *processing station* that has to pull
those frames in, optionally style them, and print them, without a guest waiting on any single step.

Three separate, independently-paced stages:

1. **Ingest** — collect images from a source that is not the kiosk's own camera: an SD card handed
   over by the photographer (multi-slot reader on a USB hub), or a tethered camera. Track every
   image, never import the same one twice, and on a card import **only what is new** so the card
   can be handed straight back.
2. **AI** — only when the event's configuration enables it.
3. **Print** — DNP, with real retry.

And the hard requirement: **with AI disabled, the whole thing must run with no internet at all.**

Much of the raw material exists. What does not exist is the thing that makes it a pipeline: a
durable, per-image ledger that survives restarts and lets the three stages run at their own speed.

---

## Build constraints

These were set deliberately and they shape every decision below.

| # | Constraint | Consequence |
|---|---|---|
| 1 | **Do not use `KioskOutboxWorker`.** A new uploader with its own queue. It may call existing `ApiService` methods. | New `EventMirrorWorker` over `evp_upload_queue` |
| 2 | **Use the existing DB, all new tables, don't touch the kiosk workflow.** | Unversioned second connection to `kiosk.db`, `CREATE TABLE IF NOT EXISTS`, `evp_` prefix |
| 3 | **Downscale to print format on copy.** The device stores the print-ready derivative; the original stays on the card. | ~4 GB per event instead of ~18 GB; native Kotlin downscaler |
| 4 | **All new files, in a new folder.** | `lib/services/event_pipeline/`, four unavoidable exceptions listed below |
| 5 | Card import: **auto-detect → auto-scan → one tap to import**, with per-file selection and a manual file-pick fallback in the same sheet. | Scan is free and automatic; import is a deliberate act |
| 6 | Auto-advance **follows event config** (`aiEnabled` → AI job, `autoPrint` → print job). | Both default off |
| 7 | Hardware is on hand. | The storage probe ships early and is measured, not assumed |

Constraints 1–3 removed most of v1's risk. That is documented in
[What the constraints bought us](#what-the-constraints-bought-us).

---

## What already exists (and what it costs us)

**Reusable as-is:**

- `lib/services/kiosk_outbox_worker.dart` — a correct claim → drain → backoff → mark loop with
  attempt caps, serialized via a `_chain` future, driven by `Timer.periodic`. The exact shape all
  stage workers should follow. **[v2]** Per constraint 1 this shape is **copied into a new file,
  not imported**.
- `lib/services/local_kiosk_db.dart` — sqflite with WAL, already open and healthy.
- `lib/services/catalog_disk_cache.dart` — the 3-layer memory→disk→API pattern that makes themes,
  settings, frames and event info survive a cold start with no WAN.
- `lib/utils/event_bulk_import.dart` — **[v2]** `parseJpegExifDateTime` (line 78) is a
  zero-dependency EXIF APP1 scan; `eventImportResolvedMime`, `eventImportMagicMime`,
  `sortEventImportItems`, `toggleEventImportSelection`, `eventImportSelected` are all directly
  reusable. This replaces v1's proposal to add the `image` package for EXIF.
- Both DSLR stacks (`canon/` PTP in Kotlin, EDSDK sidecar via `local_camera_service.dart`) and the
  DNP driver (`lib/services/dnp/`, `android/.../dnp/`) work and are not being touched structurally.
- `android/.../dnp/DnpImageProcessor.kt` and `canoncapture/DisplayDerivative.kt` — direct precedent
  for the native downscaler in Phase 2.
- `lib/screens/event_station/event_station_view_widgets.dart` — `EventStationStatsBar`,
  `EventStationStatusTabs`, `EventStationImageCarousel`. Imported by the new screens; not modified.

**Exists but points the wrong way:**

- `lib/screens/event_station/` + `lib/services/event_station_api.dart` already model
  capture/theme/print stations — but **server-brokered**. All three viewmodels are the same shape:
  `Timer.periodic` (3–4 s) → `EventStationApi.fetchBoard()` → status tabs → `claimJob` →
  `completeJob`. Jobs live on the backend, and `resolveEventPostSplashRoute`
  (`lib/utils/event_station_role.dart:39`) sends station devices to `needsInternet` when WAN is
  down. **[v2]** This becomes a parallel path, left entirely untouched — not a mirror, not a
  migration target.
- `KioskOutboxWorker` is **outbound-only**. There is no inbound ingest queue.

### `pickFromCard` is not the SD import it looks like

`EventCaptureStationViewModel.pickFromCard()` → `ImagePicker().pickMultiImage()` → tray with
checkboxes → `importSelectedAsGuests()` → per photo: create a session, then
`updateSession(userImageUrl: 'data:image/jpeg;base64,…')`. Five things make it unusable for a real
event:

1. It is the **gallery picker**, not a card volume, and the operator hand-selects every file.
   There is no way to express "import the 412 new ones".
2. **Zero dedupe.** Re-picking the same photo creates another session.
3. **Every file's bytes are held in RAM simultaneously** — `EventBulkImportItem.bytes` is a
   `Uint8List` inside a `List`. 412 × 6 MB ≈ 2.4 GB heap. That OOMs on the Amlogic box.
4. Upload is a **base64 data URL** via `updateSession` — online-only, +33% inflation.
5. `ImagePicker` downsamples via `kMaxImageWidth` / `kGalleryPickerImageQuality` — print resolution
   is lost, uncontrolled.

This is a new workflow, not a modification of that one. `pickFromCard` stays where it is.

### Findings that constrain the implementation

1. **`LocalKioskStore` cannot hold this data.** It keeps the entire ledger in RAM and calls
   `LocalKioskDb.replaceAll()` on *every* mutation (`local_kiosk_store.dart:703`), deleting and
   re-inserting every row of every table. Fine for 40 sessions a day; fatal for 3,000 photos. The
   pipeline needs a **row-level store using direct SQL**, not `KioskLedgerData`.
   **[v2] The mitigating detail:** `_replaceAllUnlocked` (`local_kiosk_db.dart:236`) deletes from a
   **hardcoded table list**. New `evp_*` tables are structurally out of its reach.
2. **`local_kiosk_db.dart` is at `_dbVersion = 1` with `onCreate` only — no `onUpgrade`.**
   **[v2]** v1 planned to fix this. v2 does not need to — see [Schema](#schema-v2).
3. **There is no `aiEnabled` flag anywhere.** AI is disabled today only as a side effect of
   `session.offline`, or `photoMode == 'FRAME_ONLY'` with zero themes, or a `tier == 'photo_strip'`
   theme.
4. **[v2] `ApiService.generateImages()` (`api_service.dart:1542`) requires a server `sessionId`
   and `originalPhotoId`.** So an AI job cannot run before that item's server mirror has landed.
   This is a hard ordering dependency between the mirror and the AI queue.
5. **[v2] `DnpPrintSize.kt` pins the downscale target**: native width **1920 px** at 300 dpi,
   largest raster 1920 × 2436 (6×8).

**Confirmed absent:** any SD-card / mass-storage / SAF / MediaStore / MTP code; CCAPI (the sidecar
README explicitly rejected it); persisted print retry (`recordPrintJob` is called only *after*
success with a hardcoded `'COMPLETED'` at `local_kiosk_settlement.dart:98`, so a failed print is
lost on restart); DNP ribbon/paper status in Dart (decoded in Kotlin — `1100` paper end, `1200`
ribbon end, `1300` jam — then thrown away as an exception string);
`<usb-device class="8" />` in `device_filter.xml`, so `USB_DEVICE_ATTACHED` never fires for a card
reader today.

---

## Architecture

```
  IngestSource (interface)          ┌──────────────────┐      ┌────────────────────┐
   ├ SdCardIngestSource     ──────► │ evp_media_items  │ ───► │ evp_pipeline_jobs  │
   ├ FolderIngestSource             │    (ledger)      │      │    ai | print      │
   └ LiveCaptureIngest              └────────┬─────────┘      └─────────┬──────────┘
          │                                  │                          │
          └─ downscale to print size         │                 ┌────────┴────────┐
             on the way in                   │            AiJobWorker      PrintJobWorker
                                             │            (needs WAN)      (fully local)
                                             │
                                             └──► EventMirrorWorker ──► backend (best effort)
                                                  (evp_upload_queue)
```

Everything below `IngestSource` is offline-capable. `AiJobWorker` is the only stage that requires
WAN, and it is never scheduled when the event has AI off. `EventMirrorWorker` is entirely
best-effort — it exists for server-side logging and future reprint, and nothing in the event flow
blocks on it.

### New folder layout — all new files

```
lib/services/event_pipeline/
  event_pipeline_db.dart          event_pipeline_queue.dart
  event_pipeline_worker.dart      event_pipeline_config.dart
  event_media_store.dart          event_mirror_worker.dart
  ai_job_worker.dart              print_job_worker.dart
  ingest/
    ingest_source.dart            ingest_diff.dart
    sd_card_ingest_source.dart    folder_ingest_source.dart
    ingest_worker.dart            live_capture_ingest.dart
    card_detect_channel.dart      image_downscale_channel.dart
lib/models/event_pipeline/        ← MediaItem, PipelineJob, PrinterConsumables, IngestCandidate
lib/screens/event_pipeline/       ← ingest station + operator console
test/services/event_pipeline/     ← mirrors the source tree
android/app/src/main/kotlin/com/srisarani/fotozenai/eventpipeline/
  ExternalStorageMethodChannel.kt EventImageDownscaler.kt
  CardDetectReceiver.kt           EventPrinterStatusMethodChannel.kt
```

**[v2] Unavoidable edits to existing files.** Constraint 4 cannot be met literally; these four are
the complete list, and nothing else is touched.

| File | Edit | Why it cannot be avoided |
|---|---|---|
| `android/.../MainActivity.kt` | 2 lines in `configureFlutterEngine` | Flutter method channels must be registered on the engine |
| `android/app/src/main/res/xml/device_filter.xml` | add `<usb-device class="8" />` | **[v2.1] Downgraded to optional.** Measured: a *runtime* receiver already sees the reader while the app is running. This file only drives the manifest filter that wakes a *closed* app on insert — irrelevant for an always-on kiosk. |
| `lib/utils/constants.dart`, `lib/app_routes.dart` | new route name + table entry | Required for any new screen |
| `pubspec.yaml` | declare `crypto` | Already resolved transitively (`pubspec.lock:330`), so no new resolution risk |

Notably **`lib/utils/event_station_role.dart` is not edited.** v1 planned to gate
`resolveEventPostSplashRoute`'s `needsInternet` branch on `aiEnabled`. v2 leaves the existing
station roles' behaviour exactly as-is; the ingest station has its own route, reached by explicit
operator navigation from the station picker or staff dashboard.

---

## Schema (v2)

**[v2] The single biggest change from v1.** That plan bumped `_dbVersion` to 2 and added an
`onUpgrade` handler to `local_kiosk_db.dart`, and called it *"the highest-risk edit in the plan — a
bad `onUpgrade` bricks the ledger on every existing booth."* That risk is now gone entirely.

`EventPipelineDb` opens **its own connection to the same `kiosk.db` path with no `version:`
argument**, so sqflite's `onCreate` / `onUpgrade` machinery never fires, then runs
`CREATE TABLE IF NOT EXISTS`. Idempotent on both a fresh and an existing database, on every launch,
forever. No migration path to write, and none to get wrong.

Three properties make this safe, all already true in the existing code:

- WAL is enabled (`local_kiosk_db.dart:41`), so a second connection is fine. Set `busy_timeout`.
- `_replaceAllUnlocked` deletes from a **hardcoded table list**, so `replaceAll()` can never reach
  `evp_*` tables.
- No `evp_*` table carries a foreign key into a kiosk table, so `PRAGMA foreign_keys = ON` is a
  non-issue.

```sql
CREATE TABLE IF NOT EXISTS evp_media_items (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT,
  source TEXT NOT NULL,          -- sdcard | folder | ptp | sidecar | device | uvc
  source_ref TEXT NOT NULL,      -- '{volumeId}:{relPath}:{size}:{mtimeMs}'   [v2: +size,+mtime]
  content_key TEXT NOT NULL,     -- sha1(size ‖ first 64KiB ‖ last 64KiB) of the ORIGINAL
  original_filename TEXT,        -- so the original is re-locatable if the card comes back
  captured_at_ms INTEGER,        -- EXIF DateTimeOriginal, read BEFORE downscale
  original_bytes INTEGER,        -- size on the card
  stored_bytes INTEGER,          -- [v2] size of the downscaled derivative we keep
  stored_path TEXT,              -- [v2] EventMediaStore relative path
  stored_width INTEGER, stored_height INTEGER,                            -- [v2]
  stage TEXT NOT NULL,           -- INGESTED|AI_QUEUED|AI_DONE|PRINT_QUEUED|PRINTED|FAILED
  remote_session_id TEXT, remote_photo_id TEXT,  -- [v2] filled by mirror; AI waits on these
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS evp_media_source_uidx  ON evp_media_items(source, source_ref);
CREATE UNIQUE INDEX IF NOT EXISTS evp_media_content_uidx ON evp_media_items(content_key);
CREATE INDEX IF NOT EXISTS evp_media_stage_idx ON evp_media_items(stage, created_at_ms);
CREATE INDEX IF NOT EXISTS evp_media_event_idx ON evp_media_items(event_id, created_at_ms);

-- [v2] identity + display only. No last_cursor: see "The cursor is demoted" below.
CREATE TABLE IF NOT EXISTS evp_ingest_sources (
  id TEXT PRIMARY KEY NOT NULL,   -- volume UUID or synthesized fingerprint
  kind TEXT NOT NULL, label TEXT,
  last_seen_at_ms INTEGER, last_scan_at_ms INTEGER,
  imported_count INTEGER NOT NULL DEFAULT 0);

CREATE TABLE IF NOT EXISTS evp_pipeline_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,             -- 'ai' | 'print'
  media_id TEXT NOT NULL, event_id TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,           -- PENDING | CLAIMED | DONE | FAILED | PAUSED   [v2: +PAUSED]
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS evp_jobs_kind_media_uidx ON evp_pipeline_jobs(kind, media_id);
CREATE INDEX IF NOT EXISTS evp_jobs_ready_idx
  ON evp_pipeline_jobs(kind, status, next_attempt_at_ms);

-- [v2] the new mirror queue. Replaces v1's "extend KioskOutboxEntity".
CREATE TABLE IF NOT EXISTS evp_upload_queue (
  id TEXT PRIMARY KEY NOT NULL,
  media_id TEXT NOT NULL,
  kind TEXT NOT NULL,             -- 'asset' | 'row'
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,           -- PENDING | CLAIMED | DONE | FAILED
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS evp_upload_kind_media_uidx ON evp_upload_queue(kind, media_id);
CREATE INDEX IF NOT EXISTS evp_upload_ready_idx ON evp_upload_queue(status, next_attempt_at_ms);

CREATE TABLE IF NOT EXISTS evp_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT);
```

---

## The card diff

Three layers, cheapest first.

- **Layer 0 — volume identity.** `evp_ingest_sources.id` = volume UUID, or a synthesized
  fingerprint (`label:totalBytes:oldest-file-path+mtime`) when no UUID is exposed. Answers
  "have I seen this card?".
- **Layer 1 — stat-only path key, zero file reads.**
  `source_ref = {volumeId}:{relPath}:{sizeBytes}:{mtimeMs}` under a UNIQUE index. Enumerate +
  `stat`, diff against the index, done. This is the workhorse and it is what makes a rescan
  instant — a re-inserted card matches every row with no file read at all.
- **Layer 2 — content key, only for Layer-1 misses.**
  `sha1(size ‖ first 64 KiB ‖ last 64 KiB)` of the **original on the card**, computed only on
  genuinely-new candidates. Catches the same photo arriving twice by different routes — tethered
  over USB during the shoot, and again from the card afterwards. Deliberately not a full-file hash:
  at 6 MB × 3,000 frames that is minutes of I/O for no extra safety.

### [v2] The Layer-1 key gains size and mtime — this fixes a real bug

v1's Tier-1 key was `{volumeId}:{relPath}` alone. When a card is reformatted and the camera's file
numbering resets to `IMG_0001` — Canon's "auto reset" numbering, a completely normal setting — that
key matches rows written from the *previous* contents of that card, and the importer **silently
skips genuinely new photos**. A false negative, which is the dangerous direction: the operator sees
"0 new", hands the card back, and the photos are gone.

Size and mtime come from the same `stat` we already perform, so this costs nothing and closes it.

### [v2] The cursor is demoted to a display field

v1 stored `ingest_sources.last_cursor` — the highest `(captured_at, filename)` imported — and
filtered the scan to entries above it. That is a correctness mechanism that breaks the moment the
photographer reinserts an older card, or the camera clock is skewed, or two bodies with different
clocks shoot to the same card.

Stat-only enumeration of 3,000 directory entries is well under a second, so the cursor buys almost
nothing while risking a silent miss. **The UNIQUE index does the work.** The cursor survives only
as the "last seen 14:32 · 1,088 imported" line in the UI, hence the `last_seen_at_ms` /
`imported_count` columns replacing it.

### Mechanism independence

Plain `File`, SAF, MediaStore and libaums **all** expose name, size and lastModified without
reading bytes, so this diff works under whichever the probe selects. That is why Phase 0 and
Phase 2's diff logic can be built and unit-tested before the probe result is in.

**[v2.1] Under MediaStore — the selected mechanism** — one `ContentResolver.query()` on
`content://media/{volumeName}/images/media` returns everything the diff needs in a single cursor:

| Column | Used for |
|---|---|
| `volume_name` | Layer 0 — card identity (`1e6f-0961`) |
| `relative_path` + `_display_name` | Layer 1 — path portion of `source_ref` |
| `_size`, `date_modified` | Layer 1 — the size/mtime portion that fixes the reformat bug |
| `datetaken` | `captured_at_ms`, **without reading the file** |
| `width`, `height`, `orientation` | downscale target maths, before decode |
| `_id` → item URI | `openInputStream()` for the downscale pass |

So on this path **Layer 2's 64 KiB read is the only file I/O in the entire diff**, and it runs only
on genuinely-new candidates. `parseJpegExifDateTime` is not needed here at all; it remains the
fallback for non-MediaStore sources (folder drop, live capture).

Under SAF, were it needed as the fallback, use a single `ContentResolver.query()` on the children
URI requesting `DOCUMENT_ID`, `DISPLAY_NAME`, `SIZE`, `LAST_MODIFIED` — **not**
`DocumentFile.listFiles()`, which issues one IPC per file and crawls on a folder with thousands of
entries.

### [v2.1] MediaStore is not a durable record

A volume's rows vanish the moment it is unmounted (measured: `Volume 1e6f-0961 not found`). Every
"already imported" number, every per-card history line, and the whole dedupe index must come from
`evp_media_items`. MediaStore is an enumeration API for the *currently inserted* card and nothing
more.

---

## [v2] Downscale on copy

The card keeps the original; the device keeps a print-ready derivative only. This is new in v2 and
it is what makes the storage problem disappear.

**Target size.** `DnpPrintSize.kt` gives the real numbers: native width **1920 px** at 300 dpi,
largest raster **1920 × 2436** (6×8). Under `DnpImageProcessor`'s cover-fit, full native quality
needs the derivative's **short side ≥ 1920**. So: scale so short side = `1920 × qualityFactor`
(default 1.0), long side capped at 4096 to bound panoramas, JPEG q88, never upscale.

A 6 MB / 24 MP original becomes roughly **1.2–1.5 MB**. A 3,000-frame event is **~4 GB instead of
~18 GB.**

**Do it natively, not in Dart.** `package:image` is already a dependency (`pubspec.yaml:42`) but is
pure Dart — decode + resize + encode of a 24 MP JPEG is ~1.5–3 s on the Amlogic box, making a
3,000-frame import a **two-hour** operation. A new Kotlin `EventImageDownscaler.kt` using
`ImageDecoder` with `setTargetSize` (hardware-assisted, and **EXIF-orientation-aware for free**)
plus `Bitmap.compress(JPEG, 88)` runs ~200–300 ms per frame — a **~15-minute** import. Run it on a
single-thread executor as `DnpUsbMethodChannel` does, so peak RAM stays one bitmap.

**Read EXIF before re-encoding.** `DateTimeOriginal` does not survive the re-encode, and it is what
`captured_at_ms` and the entire sort order depend on. Parse it from the first 64 KiB that Layer 2
already read, using `parseJpegExifDateTime` (`lib/utils/event_bulk_import.dart:78`).

### Consequences to accept — explicit sign-off wanted

- **A reprint after the card is gone reprints the derivative, not the original.** At short-side
  1920 that is visually identical for every size the DS-RX1 prints (4×6, 5×7, 6×8, 2×6), so this is
  fine in practice — but it is a **one-way door** for that event's photos. Hardware verification
  step 4 is the sign-off gate.
- **AI generation runs on the derivative too.** For a 1024–1536 px model input that is ample.
- `source_ref` and `original_filename` are recorded, so if the card comes back the original is
  re-locatable by hand.

### [v2] `EventMediaStore`, not `LocalMediaStore`

Derivatives go to `{support}/fotozen_event_media/{eventId}/{uuid}.jpg` — a **sibling** of
`fotozen_media/` (`local_media_store.dart:23`), not a prefix inside it.

v1 planned to write event media into `LocalMediaStore` via `persistCapturedGuestXFile`. That has
three unwanted effects, and a separate directory makes all three **structurally impossible** rather
than something to remember:

- `KioskOutboxWorker._enqueueUnsyncedMedia()` walks `LocalMediaStore.listAll()` and enqueues
  **every** file it finds as an asset upload. Event photos would be silently uploaded by the very
  worker constraint 1 excludes — 3,000 rows drained 8 per 30 s, roughly three hours of upload.
- `KioskDiskGuard.measure()` would count them toward `kUnsyncedMediaCapBytes` (2 GB,
  `kiosk_disk_guard.dart:6`), and `shouldBlockNewSessions()` would **block the guest booth**
  (`terms_and_conditions_viewmodel.dart:180`) partway through the event. Offline, nothing ever
  syncs, so the cap is reached and never released.
- `KioskDiskGuard.pruneSynced()` **deletes** any synced file older than `kSyncedMediaRetention`
  (7 days), so event media would evaporate a week later and kill local reprint.

Storage policy therefore reduces to a **free-space floor** — block ingest below N GB free — because
`EventMediaStore` sits outside `KioskDiskGuard` entirely. v1's whole "Storage sizing" section is
resolved.

---

## Phases

Each phase is independently shippable and leaves existing behaviour untouched throughout.

### Phase 0 — Foundations

1. `event_pipeline_db.dart` — second connection to `kiosk.db`, no `version:`,
   `CREATE TABLE IF NOT EXISTS`, `busy_timeout`. Row-level SQL only; never `LocalKioskStore` or
   `replaceAll()`.
2. `event_pipeline_queue.dart` — `enqueue`, `claimReady(kind, limit)`, `markDone`,
   `markFailed(backoff)`, `pause(kind)`, `counts(kind)`. Backoff `min(2^attempts × 30s, 15min)`
   written into `next_attempt_at_ms`; attempts capped at 8.
3. `event_pipeline_worker.dart` — the drain loop, **copying the shape** of `KioskOutboxWorker`
   (same `_chain` future serialization, `start({interval})`, `drain({limit})`,
   `drainUntilCaughtUp({onProgress})`) into a new file. Subclassed per stage. Retry classification
   is a new `isRetryableEventError`, modelled on `isRetryableIngestError`
   (`kiosk_outbox_worker.dart:73`).
4. `event_media_store.dart` — `{support}/fotozen_event_media/{eventId}/`.
5. Models under `lib/models/event_pipeline/`.

*Done when:* `flutter test` passes with new tests under `test/services/event_pipeline/`, and a
booth carrying real v1 ledger data runs a full guest session with the `evp_*` tables present and
every existing row untouched.

### Phase 1 — Storage probe

The SD mechanism cannot be chosen from the code alone. Amlogic boxes differ in whether `vold`
auto-mounts a USB card reader, and that single fact rules out either SAF or libaums. The first
deliverable is a measurement, not an implementation. Hardware is on hand, so this runs early.

`android/.../eventpipeline/ExternalStorageMethodChannel.kt` on
`com.srisarani.fotozenai/event_external_storage`, following the `DnpUsbMethodChannel` idiom
(`object` singleton, `register(engine, context)`, wired in `MainActivity`):

- `listStorageVolumes()` — per `StorageManager.getStorageVolumes()`: uuid, description,
  `isRemovable`, state, directory path, whether `createOpenDocumentTreeIntent()` is offered.
- `listUsbDevices()` — vendor/product/interface class per attached device, flagging mass-storage
  (class 8).
- `probeDirectRead(path)` — can we `File(path).list()` today, with no grant?
- `mediaStoreVolumes()` — `MediaStore.getExternalVolumeNames()`.

Plus `<usb-device class="8" />` in `device_filter.xml`, and a read-only diagnostics panel in the new
console rendering the report.

**Decision rule from the report:**

| Probe result | Mechanism | Trade-off |
|---|---|---|
| `probeDirectRead` succeeds | plain `File` APIs | Best case. No prompts, no new dependency. |
| Volume mounted + **indexed by MediaStore** | **MediaStore** ← **selected, see below** | One runtime permission, granted once, forever. No per-card prompt. |
| Volume listed, not readable, not indexed | SAF tree grant | Play-safe, but one operator tap per *unseen* card. |
| No volume, but class-8 USB device present | libaums | No filesystem prompt, but fails outright if `vold` later claims the device. |
| — | `MANAGE_EXTERNAL_STORAGE` | Simplest code, but a restricted Play permission needing category approval. Real rejection risk given we ship AABs. Avoid unless the others fail. |

---

## Probe results (2026-09-07)

Run against a **OnePlus Nord CE (EB2101), Android 13 / API 33**, with a USB multi-slot reader and
two real Canon cards. **Not the Amlogic box** — see [caveat](#the-amlogic-caveat).

### The card auto-mounts

```
sm list-volumes all  →  public:8:97 mounted 1E6F-0961
sm list-disks        →  disk:8:96
mount                →  /dev/block/vold/public:8:97 on /mnt/media_rw/1E6F-0961 type exfat
                        /dev/fuse on /storage/1E6F-0961 type fuse
/sys/block/sdg       →  .../a600000.ssusb/.../usb1/1-1/1-1.4/...  (USB mass storage)
```

`vold` auto-mounts the reader with no intervention. Card contents were the real target case:
`DCIM/100CANON` + `CANONMSC`, 1,529 files.

### `probeDirectRead` **fails** — plain `File` is ruled out

Tested as the app's genuine UID via `run-as com.srisarani.fotozenai`:

```
uid=10289(u0_a289) groups=…,1015(sdcard_rw),1028(sdcard_r),1078(ext_data_rw),…
ls /storage/                              → Permission denied
ls /storage/1E6F-0961/                    → Permission denied
ls /storage/1E6F-0961/DCIM/100CANON/      → Permission denied
dd if=…/IMG_7022.JPG                      → Permission denied
```

This is **not** a missing runtime grant. `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` are
already capped at `maxSdkVersion="32"` in `AndroidManifest.xml:21-22`, so on API 33 they do not
apply to this app at all; and `READ_MEDIA_IMAGES` gates MediaStore queries, not raw FUSE access.
Direct `File` access to a removable volume on API 30+ requires `MANAGE_EXTERNAL_STORAGE`, which we
are avoiding for Play-policy reasons.

*(`pm grant` from adb is blocked by OnePlus vendor policy, so the grant could not be toggled from
the shell. It does not change the conclusion, for the reason above.)*

### **MediaStore indexes the card fully — this is the mechanism**

```
content query --uri content://media/1e6f-0961/images/media
  --projection _display_name:_size:date_modified:relative_path:datetaken:width:height:orientation

Row: 0 _display_name=IMG_6624.JPG, _size=6921200, date_modified=1691754732,
       relative_path=DCIM/100CANON/, datetaken=1691754731900,
       width=6000, height=4000, orientation=0, mime_type=image/jpeg
…
1,511 rows
```

**One cursor returns the entire Layer-1 diff key *and* `captured_at_ms`, with zero file reads.**
`volume_name` (`1e6f-0961`) is the card UUID, so Layer-0 identity comes free from the same query.
Bytes for the downscale pass come from `ContentResolver.openInputStream(uri)`.

**[v2.1] This is better than the SAF outcome the plan expected**, and it changes two design details:

| | SAF (expected pick) | **MediaStore (actual pick)** |
|---|---|---|
| Operator cost | One tree-pick tap per *unseen card* | **One permission grant, ever** |
| Enumeration | `ContentResolver.query()` on children URI | Same, one cursor |
| `captured_at` | Read EXIF from first 64 KiB of every file | **`datetaken` column — no file read at all** |
| Play safety | Safe | Safe (`READ_MEDIA_IMAGES`, already in the manifest at line 25) |

So `parseJpegExifDateTime` is **no longer needed on the card-ingest path** — it stays only as the
fallback for sources that are not MediaStore-backed (folder drop, live capture).

### Card swap: scanner latency measured

Second card, 261 files:

```
[t+265s] volume unmounted
[t+291s] public:8:97 mounted 3432-3561    mediastore_rows=0    files_on_disk=261
[t+295s]                                  mediastore_rows=159
[t+299s]                                  mediastore_rows=192
[t+302s]                                  mediastore_rows=254   ← settled
```

**~11 s from mount to a complete index, ≈23 images/sec.** Extrapolated: ~66 s for 1,529 files,
**~2 minutes for a 3,000-frame card.**

**[v2.1] This creates a hard requirement on Phase 2.** Auto-scan-on-insert must **wait for the
scanner to settle** — poll until the row count is stable across N consecutive samples — and show a
live "Scanning card… 254 photos found" state. Scanning immediately on the mount broadcast reports a
partial count, and at t+291s it would have reported **"0 new photos"** on a card holding 261.

### Reinsertion: the "rescan imports zero" test passes

Card 1 removed, card 2 tested, then card 1 put back:

```
sm list-volumes all  →  public:8:97 mounted 1E6F-0961     ← same UUID as before removal
row count            →  1511                              ← identical
IMG_6624.JPG  _size=6921200  date_modified=1691754732  datetaken=1691754731900
IMG_6625.JPG  _size=9250690  date_modified=1691754742  datetaken=1691754741110
IMG_6626.JPG  _size=7659511  date_modified=1691754766  datetaken=1691754766830
…                                        ← every sampled tuple byte-identical
```

**Layer 0 and Layer 1 are both verified stable across a physical remove/reinsert cycle.** The
volume UUID is the FAT serial and survives; `_display_name`, `_size`, `date_modified` and
`relative_path` all return identical values. A rescan of a known card therefore matches every row
on the UNIQUE index and imports zero, with no file reads — which is the behaviour the whole feature
rests on.

**[v2.1] One fragility this exposed, and why Layer 2 earns its place.** `date_modified` is a
filesystem timestamp and *can* be rewritten by a computer that touches the card — this very card
carries macOS `._IMG_*.JPG` sidecars, so a Mac has written to it. If mtimes shift without the
photos changing, the Layer-1 key changes and those files look new. Layer 2 then catches them by
content hash, so the outcome is correct: the cost is reading 128 KiB × N (~190 MB for 1,511 files,
a few seconds) instead of zero. The two-layer design degrades to "slower", never to "wrong" —
which is the property worth having, and is a second reason not to rely on a single key.

Also visible in the data: `IMG_6629.JPG` has `date_modified=1694033384` but
`datetaken=1694072984180`, ~11 hours apart. `date_modified` is not a capture time. Use `datetaken`
for `captured_at_ms` and `date_modified` only as part of the dedupe key.

**Not yet tested:** whether MediaStore `_id` values survive a remount. The design must never key on
`_id` — and does not; `source_ref` is path + size + mtime. Item URIs are used only within a single
scan session, for `openInputStream()`.

### [v2.1] The app already receives the card-reader attach event today

Captured from the running app's logcat during a card swap — this is the existing `uvccamera`
plugin's USB device monitor, logging the reader and then correctly ignoring it:

```
UvcCameraDeviceMonitorListener: onDettach: device=UsbDevice[
  mName=/dev/bus/usb/001/004, mVendorId=1507, mProductId=1873,
  mManufacturerName=USB Storage, mProductName=USB Storage,
  UsbInterface[mClass=8, mSubclass=6, mProtocol=80]]
UvcCameraPlatform: castDeviceEvent: skip non-UVC type=detached vid=1507 pid=1873
CanonSidecar: USB device attached — requesting Canon permission / launch
CanonUsbPerm: No Canon DSLR found in USB device list
```

The reader is **VID 1507 = `0x05E3`, PID 1873 = `0x0751`** (Genesys Logic), interface
**class 8 / subclass 6 / protocol 80** — USB Mass Storage, SCSI, Bulk-Only. Exactly the class-8
device the probe predicted.

**This splits the `device_filter.xml` edit into two separate concerns, only one of which is
required:**

- **Detecting insert while the app is running** — already works. A runtime `BroadcastReceiver` on
  `ACTION_USB_DEVICE_ATTACHED` / `_DETACHED` receives every device regardless of
  `device_filter.xml`, as these logs prove. Phase 2's card detect needs only its own runtime
  receiver.
- **Launching or waking the app when a card is inserted while it is closed** — this *does* need
  `<usb-device class="8" />` in `device_filter.xml`, because that file drives the manifest intent
  filter.

For an always-on kiosk the first case is the one that matters, so the `device_filter.xml` edit
drops from "required" to "nice to have" — worth knowing, since it was listed as an unavoidable
edit to an existing file.

Two incidental notes: `CanonSidecar` wakes on the same broadcast and correctly finds no DSLR, so
the reader does not disturb the camera stacks; and `uvccamera` already enumerates full
`UsbInterface` class/subclass/protocol data, which is most of what `listUsbDevices()` was specified
to return.

### Three further findings

1. **MediaStore drops a volume's rows the instant it is unmounted.**
   `content://media/1e6f-0961/…` after removal → `IllegalArgumentException: Volume 1e6f-0961 not
   found`. MediaStore is **not** a durable record, which confirms the local-ledger architecture:
   the "1,088 already imported" count must come from `evp_media_items`, never from MediaStore.
2. **Filename numbering across cards is not monotonic.** Card 1 held `IMG_6624`–`IMG_7xxx`
   (datetaken Aug 2023); card 2 held `IMG_0631`–`IMG_0907` (datetaken 2026). A *lower* filename
   range on the *newer* card. **This is direct field evidence for demoting the cursor** — a
   cursor keyed on filename or `captured_at` would have filtered card 2 to nothing.
3. **MediaStore filters junk for free.** 1,529 files on disk → 1,511 rows; 261 → 254. The gap is
   `CANONMSC` sidecars and macOS `._IMG_*.JPG` AppleDouble stubs (4,096 bytes each), which
   MediaStore does not index as images. The ingest gets that filtering without the magic-byte
   check having to catch it.

### The Amlogic caveat

Everything above is a **OnePlus/OxygenOS on API 33** result. The probe existed to answer whether
the *Amlogic box* auto-mounts a reader and indexes it, and a phone result does not transfer: AOSP
Android TV builds sometimes ship a reduced MediaProvider, and `vold` behaviour on those boxes is
exactly the variable the probe was written to measure.

**Re-run this probe on the Amlogic box before building `SdCardIngestSource`.** If MediaStore does
not index removable volumes there, SAF is the fallback and the `IngestSource` interface is what
makes that swap cheap. The measured numbers to reproduce are: volume mounts, `probeDirectRead`
result as the app UID, MediaStore row count, scanner settling time, and UUID/tuple stability across
a reinsert.

### Probe summary

| Question | Result on OnePlus / API 33 | Confidence on Amlogic |
|---|---|---|
| Does `vold` auto-mount the reader? | **Yes**, exfat, `public:8:97` | Must re-measure |
| Can the app read it directly (`File`)? | **No** — denied at the app UID | High: API-level policy, not vendor |
| Does MediaStore index the card? | **Yes** — 1,511 rows, full metadata | Must re-measure |
| Scanner settling time | **~11 s / 261 files** (~23 img/s) | Must re-measure |
| Volume UUID stable across reinsert? | **Yes** — `1E6F-0961` both times | High: FAT serial |
| `(path, size, mtime)` stable across reinsert? | **Yes** — byte-identical | High: filesystem property |
| Rows survive unmount? | **No** — volume dropped entirely | High: documented behaviour |

*Done when:* the report renders on **the box** with the reader attached, and the mechanism is
confirmed or changed **in this document**.

### Phase 2 — Ingest

- `ingest/ingest_source.dart` — `abstract class IngestSource` with `id`, `label`,
  `Future<List<IngestCandidate>> listAll()` (stat-only), `Stream<List<int>> openRead(candidate)`.
  This interface is the seam that lets the probe outcome — and a future `CcapiSource` — drop in
  without touching the pipeline.
- `ingest/sd_card_ingest_source.dart` — whichever mechanism Phase 1 selects.
- `ingest/folder_ingest_source.dart` — any directory path. Unblocks testing before the probe lands,
  and covers a LAN drop folder later.
- `ingest/ingest_diff.dart` — the three-layer diff. Pure and fully unit-testable.
- `ingest/ingest_worker.dart` — scan → diff → **stream original → native downscale → write
  derivative** → insert `evp_media_items` → auto-advance per event config → enqueue mirror. Never
  holds more than one image in memory at a time. This is the fix for `pickFromCard`'s 2.4 GB heap.
- `ingest/live_capture_ingest.dart` — registers stills the app itself shoots (PTP / sidecar / UVC /
  CameraX) as `evp_media_items` too. **Deliberately sequenced last in this phase**: it is the one
  piece needing a call site inside an existing file (`adoptExternalCapture`,
  `photo_capture_viewmodel.dart:2339`), so it lands as a single guarded line once everything else
  is proven. Without it the pipeline only ever sees card imports.
- **Card detect** — `ACTION_MEDIA_MOUNTED` / `ACTION_USB_DEVICE_ATTACHED` receiver in the same
  Kotlin package, surfaced to Dart as an `EventChannel` stream. Auto-scan on insert.
  **[v2.1] The scan must wait for the media scanner to settle**, not fire on the mount broadcast.
  Measured: a 261-file card mounts with **0 MediaStore rows** and takes ~11 s to reach its full
  254 (~23 img/s, so ~2 min for a 3,000-frame card). Scanning on the broadcast would have shown
  **"0 new photos"** on a full card. Poll the row count until it is stable across N consecutive
  samples, with a live "Scanning card… 254 photos found" state and an explicit
  "still scanning" indicator, so the operator never sees a settled-looking partial count.
- **Screen** under `lib/screens/event_pipeline/`, on its own route, importing the existing station
  chrome widgets. The server-brokered Capture station is left completely untouched.
- **Import sheet** — "412 new · 1,088 already imported", all-new selected by default, per-file
  toggles, and a "Pick files manually…" button. Reuses `toggleEventImportSelection`,
  `eventImportSelected`, `sortEventImportItems`, `parseJpegExifDateTime`, `eventImportResolvedMime`
  from `lib/utils/event_bulk_import.dart` — but holding **paths and metadata, never bytes**.
- Terminal state: **"Safe to remove card."** That state is the whole point of the feature.
- Optional **"Watch this card"** toggle — re-scan every 10 s and auto-import — for when the card
  stays in the reader all event. Default off.

**Also fix here:** `android/.../canon/capture/CaptureStorage.kt:53` gates on
`Environment.isExternalStorageManager()`, but `MANAGE_EXTERNAL_STORAGE` is never declared in
`AndroidManifest.xml` — so on API 30+ that check is always false and PTP originals silently land in
app-scoped storage instead of `/sdcard/FotozenCaptures`. Given the Play Store AAB releases
(`docs/android-playstore-aab-release-guide.md`), **deleting the dead branch and its misleading
KDoc is the safer fix** than declaring a restricted permission.

*Done when:* a card in the reader imports only new frames; a rescan imports zero; a **reformatted
and reshot** card still imports its new frames; a photo that arrived both tethered and on the card
produces exactly one `evp_media_items` row.

### Phase 3 — Event config + AI queue

1. **Config.** `event_pipeline_config.dart` over `SharedPreferences` — `aiEnabled`, `printEnabled`,
   `autoPrint`, `defaultCopies`, `qualityFactor`, `mirrorEnabled`. Mirrors `KioskManager`'s
   override idiom (null = inherit). Surfaced on the new console so a box that has never reached the
   backend can still run the event.
   **[v2]** Backend flags from `/api/event/by-code/:code` are read **if present** via a new parser
   in the new folder — `lib/models/event_info_model.dart` is **not** edited, as v1 proposed.
   Back-compatible defaults: `aiEnabled = photoMode != 'FRAME_ONLY'`,
   `printEnabled = settings.printerEnabled`. Cached values already survive a cold offline start via
   `EventManager.cacheVerifyResult()` (`event_manager.dart:138`) → `CatalogDiskCache`.
2. **`ai_job_worker.dart`** — claims `kind='ai'` jobs, ensures the item's server mirror exists
   (`remote_session_id` / `remote_photo_id`), then calls `ApiService.generateImages()`. Two things
   differ from the guest flow: it is **batch** (no guest waiting), and the result is written back
   to `evp_media_items` rather than into a live `SessionData`.
   **[v2] Ordering dependency:** `generateImages` needs a server session, so an AI job cannot run
   before its mirror has landed. Such items are **re-queued with backoff, not failed.**
3. **Offline.** The existing comment on `KioskOfflineUx.shouldSkipAiGeneration`
   (`lib/utils/kiosk_offline_ux.dart:16`) — *"Do not queue AI on the line"* — is correct **for the
   live guest booth** and is not touched. The event pipeline is the opposite case and queues
   deliberately. **[v2]** Rather than v1's `shouldRunAiPipeline` addition to that file, the new
   worker carries its own gate and a comment explaining the difference — or someone will "fix" it
   later.

*Done when:* an AI-disabled event runs ingest → print end to end in aeroplane mode, and an
AI-enabled event queues, generates, and survives an app restart mid-generation.

### Phase 4 — Print queue

1. **`print_job_worker.dart`** over `evp_pipeline_jobs(kind='print')`, draining to the existing
   `PrintService.printImageSilent()` (`print_service.dart:53`) / `DnpPrintBridge`. This is the
   **first time a failed print is persisted and retried** — today it is logged and lost.
2. **Typed model** `models/event_pipeline/print_job.dart`. Records the real terminal status,
   unlike the hardcoded `'COMPLETED'` at `local_kiosk_settlement.dart:98`.
   **[v2]** `LocalKioskStore.upsertPrintJob` is left alone; the guest-booth print path is unchanged.
3. **Consumables.** New `EventPrinterStatusMethodChannel.kt` exposing the codes
   `DnpUsbPrinter.printerStatusMessage()` (`DnpUsbPrinter.kt:324`) already decodes — `1100` paper
   end, `1200` ribbon end, `1300` jam, `1500` size mismatch — plus `INFO FREE_PBUFFER`. Surfaced as
   `models/event_pipeline/printer_consumables.dart`. **Pause the queue (status `PAUSED`) rather
   than burning attempts** when ribbon or paper is out: the naive version exhausts 8 retries
   against an empty printer and marks the entire event failed.
4. Auto-print when `autoPrint`; otherwise the operator releases jobs from the console.

*Done when:* pulling the ribbon mid-queue pauses rather than fails, and reloading resumes without
an app restart.

### Phase 5 — Mirror uploader

**[v2] Replaces v1's "extend `KioskOutboxEntity` with `media_item` / `pipeline_job`".**

`event_mirror_worker.dart` over `evp_upload_queue` — a **new worker, fully independent of
`KioskOutboxWorker`**, with its own timer, backoff and concurrency limit. It calls the existing API
directly, per constraint 1:

- `ApiService.ingestKioskAsset(kioskCode:, prefix:, filename:, bytes:)` (`api_service.dart:218`)
  for the derivative. Already idempotent, and generic over `prefix`, so an
  `event-originals/{eventId}` prefix needs no backend change.
- `ApiService.ingestKioskEntities(kioskCode:, items:)` (`api_service.dart:190`) for stage rows.

**Open question — verify before building this phase.** `/api/kiosk/ingest` takes arbitrary `items`
maps keyed by `entityType`. If the backend rejects unknown types, stage mirroring needs either a
backend addition or a fallback to the session path (`acceptTermsAndCreateSession` +
`updateSession`, which is what `pickFromCard` does today and is known to work). **Asset upload is
unaffected either way**, so a failure here degrades logging, not the pipeline.

A **"mirror now / after hours"** toggle sits on the console — 3,000 uploads will otherwise saturate
the venue link mid-event.

*Done when:* an event run offline all day mirrors cleanly once WAN returns, and a mid-upload kill
resumes without duplicating rows.

### Phase 6 — Operator console

`lib/screens/event_pipeline/` gains a local-ledger console: counts per stage, failed jobs with
retry, per-card import history, free-space headroom, the Phase 1 probe report, the config switches,
and an **"Event complete — purge derivatives"** action. Read entirely from `evp_*` tables, with no
server dependency.

**[v2]** v1 planned to extend `lib/screens/staff/staff_dashboard_view.dart`. v2 keeps this in the
new folder per constraint 4; the staff dashboard gets at most a navigation entry.

---

## What the constraints bought us

Worth stating plainly, because constraints 1–3 removed most of v1's risk rather than adding work:

| v1 risk | Status in v2 |
|---|---|
| `_dbVersion` 1→2 + `onUpgrade`; a bad migration bricks every booth's ledger | **Gone.** `CREATE TABLE IF NOT EXISTS` on an unversioned second connection. |
| 18 GB of originals blows the 2 GB `KioskDiskGuard` cap and blocks the guest booth mid-event | **Gone.** ~4 GB of derivatives, in a directory the guard never scans. |
| `pruneSynced()` deletes event media after 7 days, killing local reprint | **Gone.** Different directory. |
| `_enqueueUnsyncedMedia()` silently uploads all 3,000 photos through the kiosk outbox | **Gone.** Separate store, separate uploader. |
| Path-only dedupe key silently skips new photos after a card reformat | **Fixed.** Key includes size and mtime. |
| Cursor-based scan filtering misses photos on clock skew or card reinsertion | **Fixed.** Cursor demoted to display; the UNIQUE index is the mechanism. |

**Remaining real risks**, in order:

1. **The probe outcome** (Phase 1) — which is why it is measured early rather than assumed.
2. **The derivative-only one-way door** (Phase 2) — flagged above, gated on hardware step 4.
3. **The `/api/kiosk/ingest` entity-type question** (Phase 5) — verified before building, and it
   degrades logging rather than the pipeline.

---

## Verification

```bash
cd photobooth
flutter analyze lib/
flutter test
flutter test --coverage && dart run tool/verify_coverage_scope.dart
```

New tests follow the repo's established convention — **manual fakes by subclass-and-override, not
mockito** (which is not a dependency). `test/flutter_test_config.dart` already wires
`sqfliteFfiInit()` suite-wide, so DB tests work out of the box. Mirror
`test/services/event_pipeline/` against the new source dirs; inject `nowMs` / `newId` /
`resolveDirectory` as `local_kiosk_store_test.dart` does; fake the native channels by subclassing
the real client as `dnp_print_transport_test.dart` does.

Cases that specifically must have tests:

- **Reformatted card** — same filename, different size/mtime → a new row, *not* skipped.
- **Cross-route duplicate** — tethered + card → exactly one row.
- **Ribbon out** — queue pauses, attempts do not increment.
- **Coexistence** — `evp_*` tables survive a `LocalKioskStore` mutation that calls `replaceAll()`.
- **Downscale sizing** — short side lands on 1920, EXIF orientation applied, never upscaled.
- **AI ordering** — an item whose mirror has not landed is re-queued, not failed.

On hardware, in order:

1. **Coexistence** — install over an existing build carrying real v1 ledger data; run a guest
   session end to end; confirm sessions, payments, receipts and outbox rows are all untouched, and
   the `evp_*` tables were created alongside.
2. **Probe** — attach the multi-slot reader through the hub, capture the Phase 1 report, pick the
   SD mechanism, and **update this document with the result**.
3. **Ingest** — import a card; rescan → zero new; refill the card → only the new frames;
   **reformat and reshoot → new frames still detected**; verify "Safe to remove".
4. **Downscale** — print from a derivative against a print from the original at 4×6, 5×7 and 6×8.
   **This is the sign-off for the one-way door.**
5. **Offline** — aeroplane mode, AI-off event, cold start → ingest → print with no WAN.
6. **Print retry** — pull the ribbon mid-queue → pause, not failure; reload → resume, no restart.
7. **Restart resilience** — kill the app mid-AI-queue and mid-print-queue; confirm both resume.
8. **Volume** — 3,000-frame import at the box's real memory ceiling; watch heap, wall-clock and disk.

---

## Decisions taken

- **Queues are local-first**, with the backend as a best-effort mirror through a **new, dedicated
  uploader**. This is the only arrangement that satisfies the offline requirement.
- **[v2] The device stores print-ready derivatives, not originals.** Originals stay on the card.
  This is what collapses the storage problem, and it is a one-way door for any photo whose card has
  gone home.
- **[v2] New tables in the existing DB via an unversioned connection**, so no migration is written
  and none can be got wrong.
- **[v2] Event media lives in its own directory**, outside `KioskDiskGuard` and
  `KioskOutboxWorker`'s reach, by construction rather than by convention.
- **[v2] The existing server-brokered station path is untouched** — not migrated, not mirrored,
  not re-routed. The new pipeline is a parallel workflow on its own route.
- **Event config comes from backend flags with a local override.** The backend stays
  authoritative; the override means a box that has never reached the backend for this event can
  still run it.
- **Card import is auto-detected and auto-scanned, but imports on one tap.** Scanning is
  read-only and cheap; importing commits disk and, with AI on, real spend — and the tap is what
  makes "Safe to remove card" mean something.
- **CCAPI is deferred.** Two USB DSLR stacks already work, and the sidecar README explicitly
  rejected CCAPI because the requirement was USB. The `IngestSource` interface is the seam it
  plugs into later.

## Out of scope

- CCAPI (above).
- The server-brokered `/api/event/station/*` board and its three screens.
- `KioskOutboxWorker`, `LocalMediaStore`, `KioskDiskGuard`, `LocalKioskStore`,
  `EventInfoModel`, `event_station_role.dart` — all untouched.
- Web — the whole pipeline is `!kIsWeb`, matching the existing `LocalKioskStore` guard.
- Backend work, beyond confirming the Phase 5 entity-type question.
