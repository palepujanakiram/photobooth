# Event pipeline: Ingest → AI → Print, offline-capable

> **Status: draft, pending POC.** Phase 1a (the storage probe) is a deliberate
> measurement step — the SD-card mechanism is *not* decided yet, and this document
> will be updated once a real multi-slot reader has been attached to the box and the
> probe report read. Everything downstream of that choice is stable.

## Context

Today the app is a **guest-facing kiosk**: one guest, one session, one photo, taken and
processed and printed synchronously while they stand there. The event use case is different
— a photographer shoots hundreds of frames, and the booth is a *processing station* that has
to pull those frames in, optionally style them, and print them, without a guest waiting on
any single step.

Three separate, independently-paced stages are wanted:

1. **Ingest** — collect images from a source that is not the kiosk's own camera: an SD card
   handed over by the photographer (multi-slot reader on a USB hub), or a tethered camera.
   Track every image, never import the same one twice, and on a card import **only what is
   new** so the card can be handed straight back.
2. **AI** — only when the event's configuration enables it.
3. **Print** — DNP, with real retry.

And the hard requirement: **with AI disabled, the whole thing must run with no internet at
all.**

Much of the raw material exists. What does not exist is the thing that makes it a pipeline:
a durable, per-image ledger that survives restarts and lets the three stages run at their own
speed.

---

## What already exists (and what it costs us)

**Reusable as-is:**

- `lib/services/kiosk_outbox_worker.dart` — a correct claim → drain → backoff → mark
  loop with attempt caps, serialized via a `_chain` future, driven by `Timer.periodic`.
  This is the exact shape all three stage workers should copy. `isRetryableIngestError`
  is directly reusable.
- `lib/services/local_kiosk_db.dart` — sqflite with WAL, already open and healthy.
- `lib/services/local_media_store.dart` + `local_guest_media_write.dart` — durable JPEG
  storage at `{support}/fotozen_media/{prefix}/{uuid}.jpg` with a `/api/img/...` URL form.
  `persistCapturedGuestXFile()` is the funnel every new image must pass through.
- `lib/services/catalog_disk_cache.dart` — the 3-layer memory→disk→API pattern that makes
  themes, settings, frames and event info survive a cold start with no WAN.
- Both DSLR stacks (`canon/` PTP in Kotlin, EDSDK sidecar via `local_camera_service.dart`)
  and the DNP driver (`lib/services/dnp/`, `android/.../dnp/`) work and are not being touched
  structurally.
- `lib/screens/photo_capture/photo_capture_viewmodel.dart` `adoptExternalCapture()` — the
  purpose-built seam for injecting an externally-produced still. Direct-PTP is its only
  current caller.

**Exists but points the wrong way:**

- `lib/screens/event_station/` + `lib/services/event_station_api.dart` already model
  capture/theme/print stations — but **server-brokered**. Jobs live on the backend and
  `resolveEventPostSplashRoute` sends station devices to `needsInternet` when WAN is down.
  This becomes the *mirror*, not the source of truth.
- `KioskOutboxWorker` is **outbound-only**. There is no inbound ingest queue.

**Three findings that shape the plan:**

1. **`LocalKioskStore` cannot hold this data.** It keeps the entire ledger in RAM and calls
   `LocalKioskDb.replaceAll()` on *every* mutation (`local_kiosk_store.dart:699`), which
   deletes and re-inserts every row of every table. Fine for 40 sessions a day; fatal for
   3,000 ingested photos. The pipeline tables need a **row-level store using direct SQL on
   the same `Database` handle**, not `KioskLedgerData`.
2. **`local_kiosk_db.dart` is at `_dbVersion = 1` with `onCreate` only — no `onUpgrade`.**
   Adding any table requires writing that migration path first.
3. **There is no `aiEnabled` flag anywhere.** AI is disabled today only as a side effect of
   `session.offline`, or `photoMode == 'FRAME_ONLY'` with zero themes, or a
   `tier == 'photo_strip'` theme.

**Confirmed absent:** any SD-card / mass-storage / SAF / MediaStore / MTP code; CCAPI (the
sidecar README explicitly rejected it); persisted print retry (`recordPrintJob` is called
only *after* success with a hardcoded `'COMPLETED'`, so a failed print is lost on restart);
DNP ribbon/paper status in Dart (decoded in Kotlin — `1100` paper end, `1200` ribbon end,
`1300` jam — then thrown away as an exception string).

---

## Architecture

```
   ┌── IngestSource ──┐
   │  SdCardSource    │        ┌─────────────┐        ┌──────────────┐
   │  PtpCardSource   ├──────► │ media_items │ ─────► │ pipeline_jobs│
   │  LiveCaptureSrc  │        │  (ledger)   │        │  ai | print  │
   │  (CcapiSource)   │        └─────────────┘        └──────┬───────┘
   └──────────────────┘               │                      │
                                      │              ┌───────┴────────┐
                                      │         AiJobWorker      PrintJobWorker
                                      │         (needs WAN)      (fully local)
                                      │
                                      └──► KioskOutboxWorker ──► backend (best effort)
```

Everything below the ingest sources is offline-capable. `AiJobWorker` is the only stage that
requires WAN, and it is skipped entirely when the event has AI off.

### Schema v2 (new tables, direct SQL, no `KioskLedgerData`)

```sql
CREATE TABLE media_items (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT, session_id TEXT,
  source TEXT NOT NULL,          -- sdcard | ptp | sidecar | device | uvc | ccapi
  source_ref TEXT NOT NULL,      -- '{volumeId}:{relPath}' | 'ptp:{handle}' | '{uuid}'
  content_key TEXT NOT NULL,     -- see dedupe below
  original_filename TEXT, captured_at_ms INTEGER, bytes INTEGER,
  relative_path TEXT,            -- LocalMediaStore relative path
  stage TEXT NOT NULL,           -- INGESTED|AI_QUEUED|AI_DONE|PRINT_QUEUED|PRINTED|FAILED
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
CREATE UNIQUE INDEX media_items_content_uidx ON media_items(content_key);
CREATE UNIQUE INDEX media_items_source_uidx  ON media_items(source, source_ref);
CREATE INDEX media_items_stage_idx ON media_items(stage, created_at_ms);
CREATE INDEX media_items_event_idx ON media_items(event_id, created_at_ms);

CREATE TABLE ingest_sources (      -- per-card / per-camera cursor
  id TEXT PRIMARY KEY NOT NULL,    -- volume UUID or camera serial
  kind TEXT NOT NULL, label TEXT,
  last_cursor TEXT,                -- highest (captured_at, filename) seen
  last_captured_at_ms INTEGER, last_scan_at_ms INTEGER,
  imported_count INTEGER NOT NULL DEFAULT 0);

CREATE TABLE pipeline_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,              -- 'ai' | 'print'
  media_id TEXT NOT NULL, event_id TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,            -- PENDING | CLAIMED | DONE | FAILED
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL);
CREATE UNIQUE INDEX pipeline_jobs_kind_media_uidx ON pipeline_jobs(kind, media_id);
CREATE INDEX pipeline_jobs_ready_idx ON pipeline_jobs(kind, status, next_attempt_at_ms);
```

### Dedupe (two tiers, cheap first)

- **Tier 1 — `(source, source_ref)`**: for a card, `{volumeUuid}:{DCIM/100CANON/IMG_0042.JPG}`.
  Catches a re-scan of the same card instantly, with no file read at all.
- **Tier 2 — `content_key`**: `sha1(bytes_length + first 64 KiB + last 64 KiB)`. Catches the
  *same photo arriving by a different route* — e.g. tethered over USB during the shoot and
  again from the card afterwards. Deliberately not a full-file hash: at 6 MB × 3,000 frames
  a full hash is minutes of I/O for no extra safety.

### Incremental card sync

`ingest_sources.last_cursor` stores the highest `(captured_at_ms, filename)` imported for that
volume UUID. A rescan enumerates directory entries, filters to those above the cursor, and only
then reads bytes. An unknown card (new UUID) is a full scan. This is what makes "sync only the
latest photos, then hand the card back" a few seconds rather than a full re-read.

---

## Phases

Each phase is independently shippable and leaves existing behaviour untouched until the last
wiring step.

### Phase 0 — Foundations (no behaviour change)

1. **DB migration path.** `lib/services/local_kiosk_db.dart`: bump `_dbVersion` to 2, add an
   `onUpgrade` handler and extract the v2 DDL into `_createPipelineSchema(db)` called from
   both `onCreate` and `onUpgrade`. This is the highest-risk edit in the plan — a bad
   `onUpgrade` bricks the ledger on every existing booth. Test both a fresh `onCreate` and a
   v1→v2 upgrade against a real v1 file.
2. **`lib/services/pipeline/event_pipeline_db.dart`** — row-level SQL over the shared
   `Database` from `LocalKioskDb.database`. Must **not** route through `LocalKioskStore`'s
   in-RAM ledger or `replaceAll()`.
3. **`lib/services/pipeline/pipeline_job_queue.dart`** — `enqueue`, `claimReady(kind, limit)`,
   `markDone`, `markFailed(backoff)`, `counts(kind)`. Backoff: `min(2^attempts × 30s, 15min)`
   written into `next_attempt_at_ms`; cap attempts at 8, reusing `isRetryableIngestError`
   from `kiosk_outbox_worker.dart`.
4. **`lib/services/pipeline/pipeline_worker.dart`** — the drain loop, lifted from
   `KioskOutboxWorker` (same `_chain` serialization, `start({interval})`, `drain({limit})`,
   `drainUntilCaughtUp({onProgress})`). Subclassed per stage.
5. **Models:** `lib/models/media_item.dart`, `lib/models/pipeline_job.dart` — typed, replacing
   the untyped `Map<String, dynamic>` payloads the current ledger uses.

*Done when:* `flutter test` passes with new tests under `test/services/pipeline/`, and a
booth upgraded from a v1 DB keeps all its sessions, payments and outbox rows.

### Phase 1 — Ingest

**1a. Storage probe (POC — do this first, it decides 1b).**

The SD mechanism cannot be chosen from the code alone. Amlogic boxes differ in whether `vold`
auto-mounts a USB card reader, and that single fact rules out either SAF or libaums. So the
first deliverable is a measurement, not an implementation.

- New `android/.../ExternalStorageMethodChannel.kt` on
  `com.srisarani.fotozenai/external_storage`, following the `DnpUsbMethodChannel` idiom
  (`object` singleton, `register(engine, context)`, wired in `MainActivity`):
  - `listStorageVolumes()` → per `StorageManager.getStorageVolumes()`: uuid, description,
    `isRemovable`, state, directory path, whether `createOpenDocumentTreeIntent()` is offered.
  - `listUsbDevices()` → vendor/product/interface class per attached device, flagging
    mass-storage (class 8).
  - `probeDirectRead(path)` → can we `File(path).list()` today, without any grant?
  - `mediaStoreVolumes()` → `MediaStore.getExternalVolumeNames()`.
- A read-only diagnostics panel reachable from the staff dashboard that renders the report.
- Add `<usb-device class="8" />` to `android/app/src/main/res/xml/device_filter.xml` so
  `USB_DEVICE_ATTACHED` fires for the reader at all.

**Decision rule from the report:**

| Probe result | Mechanism | Trade-off |
|---|---|---|
| `probeDirectRead` succeeds | plain `File` APIs | Best case. No prompts, no new dependency. |
| Volume listed, not directly readable | **SAF tree grant** | Expected outcome, and Play-safe. One operator tap per *unseen* card; persisted grants mean a returning card is silent. |
| No volume, but class-8 USB device present | **libaums** | No filesystem prompt, but fails outright if `vold` later claims the device. |
| — | `MANAGE_EXTERNAL_STORAGE` | Simplest code, but a restricted Play permission needing category approval. Real rejection risk given we ship AABs. Avoid unless the others fail. |

**1b. Ingest sources.**

- `lib/services/ingest/ingest_source.dart` — `abstract class IngestSource` with
  `id`, `label`, `Future<List<IngestCandidate>> listNew(String? cursor)`,
  `Future<List<int>> readBytes(IngestCandidate)`. This interface is what lets a `CcapiSource`
  drop in later without touching the pipeline.
- `lib/services/ingest/sd_card_ingest_source.dart` — implements whichever mechanism 1a
  selects, behind that interface. EXIF `DateTimeOriginal` read for `captured_at_ms` (reuse
  the existing `image` package rather than adding a dependency).
- `lib/services/ingest/ingest_worker.dart` — scan → dedupe → `persistCapturedGuestXFile()`
  into `LocalMediaStore` → insert `media_items` → advance `ingest_sources.last_cursor`.
- `lib/services/ingest/live_capture_ingest.dart` — register stills the app itself shoots
  (PTP / sidecar / UVC / CameraX) as `media_items` too, called from
  `adoptExternalCapture()` in `photo_capture_viewmodel.dart:2339` and from
  `persistCapturedGuestXFile`. Without this the pipeline only sees card imports.
- Operator ingest screen: card detected → "412 new photos, 1,088 already imported" → Import
  → progress → **"Safe to remove card"**. That last state is the whole point of the feature.

**Also fix here:** `android/.../canon/capture/CaptureStorage.kt` gates on
`Environment.isExternalStorageManager()`, but `MANAGE_EXTERNAL_STORAGE` is never declared in
`AndroidManifest.xml` — so on API 30+ that check is always false and PTP originals silently
land in app-scoped storage instead of `/sdcard/FotozenCaptures`. Either declare the permission
or delete the dead branch and its misleading KDoc. Given the Play Store AAB releases
(`docs/android-playstore-aab-release-guide.md`), **deleting the branch is the safer fix**.

*Done when:* a card in the reader imports only new frames, a rescan imports zero, and a photo
that arrived both tethered and on the card produces exactly one `media_items` row.

### Phase 2 — Event config + AI queue

1. **Config.** Extend `lib/models/event_info_model.dart` with `aiEnabled`, `printEnabled`,
   `autoPrint`, `defaultCopies`, `ingestSources`, parsed from `/api/event/by-code/:code`.
   Back-compatible defaults when the backend omits them: `aiEnabled = photoMode != 'FRAME_ONLY'`,
   `printEnabled = settings.printerEnabled`. Persist through the existing
   `EventManager.cacheVerifyResult()` → `CatalogDiskCache`, so a cold offline start still
   knows the event's shape.
2. **Local override.** `lib/services/pipeline/event_pipeline_config.dart` over
   `SharedPreferences`, mirroring `KioskManager`'s override idiom (null = inherit). Surfaced
   on a staff screen so a box that has never reached the backend can still be configured.
3. **`AiJobWorker`** — claims `kind='ai'` jobs and calls the existing
   `ApiService.generateImages()` path. Two things differ from the guest flow: it is
   **batch** (no guest waiting), and the result is written back to `media_items` rather than
   into a live `SessionData`.
4. **Offline.** Add `KioskOfflineUx.shouldRunAiPipeline({required bool aiEnabled, required
   bool sessionOffline})`. Note the existing comment on `shouldSkipAiGeneration` — *"Do not
   queue AI on the line"* — is correct **for the live guest booth** and must stay; the event
   pipeline is the opposite case and queues deliberately. Worth a comment saying so, or
   someone will "fix" it later.
5. **Station routing.** `lib/utils/event_station_role.dart` `resolveEventPostSplashRoute`
   currently returns `needsInternet` for any station role with `wanAvailable == false`. Gate
   that on `aiEnabled` — an AI-off event must boot straight to its station with no WAN.

*Done when:* an AI-disabled event runs ingest → print end to end in aeroplane mode, and an
AI-enabled event queues, generates, and survives an app restart mid-generation.

### Phase 3 — Print queue

1. **`PrintJobWorker`** over `pipeline_jobs(kind='print')`, draining to the existing
   `DnpPrintBridge` / `PrintService.printImageSilent()`. This is the first time a **failed**
   print is persisted and retried — today it is logged and lost.
2. **Typed model.** `lib/models/print_job.dart`, replacing the untyped map in
   `LocalKioskStore.upsertPrintJob`. Record the real terminal status instead of the
   hardcoded `'COMPLETED'` in `local_kiosk_settlement.dart`.
3. **Consumables.** Add `queryStatus` to `DnpUsbMethodChannel.kt` exposing the codes
   `DnpUsbPrinter.printerStatusMessage()` already decodes (`1100` paper end, `1200` ribbon
   end, `1300` jam, `1500` size mismatch) plus `INFO FREE_PBUFFER`. Surface as
   `lib/models/printer_consumables.dart`. **Pause the queue rather than burning attempts**
   when the ribbon or paper is out — the current code would exhaust 8 retries against an
   empty printer and mark everything failed.
4. Auto-print when `event.autoPrint`; otherwise the operator releases jobs from the console.

*Done when:* pulling the ribbon mid-queue pauses rather than fails, and reloading resumes
without an app restart.

### Phase 4 — Operator console

Extend `lib/screens/staff/staff_dashboard_view.dart` (which already has a clean
`StaffDashboardGateway` interface and KPI tiles) with a local-ledger event view: counts per
stage, failed jobs with retry, per-card import history, disk headroom via the existing
`KioskDiskGuard`, and the Phase 1a storage probe. Today the dashboard is 100% server-backed
and reads nothing from `LocalKioskStore` — this is the first local-first screen.

Also mirror `media_items` and `pipeline_jobs` to the backend through the existing outbox
(`KioskOutboxEntity` gains `media_item` / `pipeline_job`), which is what keeps the existing
server-brokered `/api/event/station/board` useful for multi-device visibility.

---

## Storage sizing (settle before Phase 1 ships)

`KioskDiskGuard` caps **unsynced** guest JPEGs at 2 GB (`kUnsyncedMediaCapBytes`) and
`shouldBlockNewSessions()` blocks the booth when that is hit. A 3,000-frame event at 6 MB is
18 GB. For an AI-off offline event nothing ever syncs, so the cap is reached almost
immediately and the booth stops. Phase 1 must either raise the cap for event mode, or exempt
`media_items`-owned files from it and give them their own retention policy. Decide this with
a real event's frame count in hand.

---

## Verification

```bash
cd photobooth
flutter analyze lib/
flutter test
flutter test --coverage && dart run tool/verify_coverage_scope.dart
```

New tests follow the repo's established convention — **manual fakes by subclass-and-override,
not mockito** (which is not a dependency). `test/flutter_test_config.dart` already wires
`sqfliteFfiInit()` suite-wide, so DB tests work out of the box. Mirror `test/services/pipeline/`
and `test/services/ingest/` against the new source dirs; inject `nowMs` / `newId` /
`resolveDirectory` as `local_kiosk_store_test.dart` does, and fake the native channels by
subclassing the real client as `dnp_print_transport_test.dart` does.

On hardware, in order:

1. **Migration:** install over an existing build carrying real v1 ledger data; confirm
   sessions, payments, receipts and outbox rows all survive.
2. **Probe:** attach the multi-slot reader through the hub, capture the Phase 1a report,
   and pick the SD mechanism from it. **Update this document with the result.**
3. **Ingest:** import a card; rescan and confirm zero new; refill the card and confirm only
   the new frames import; verify the "safe to remove" state.
4. **Offline:** aeroplane mode, AI-off event, cold start — confirm it boots to its station
   (not `needsInternet`) and completes ingest → print.
5. **Print retry:** pull the ribbon mid-queue, confirm pause not failure, reload, confirm resume.
6. **Restart resilience:** kill the app mid-AI-queue and mid-print-queue; confirm both resume.

---

## Decisions taken

- **Queues are local-first**, with the backend as a best-effort mirror through the existing
  outbox. This is the only arrangement that satisfies the offline requirement.
- **Event config comes from backend flags with a local override.** Backend stays
  authoritative; the override means a box that has never reached the backend for this event
  can still run it.
- **CCAPI is deferred.** Two USB DSLR stacks already work, and the sidecar README explicitly
  rejected CCAPI because the requirement was USB. The `IngestSource` interface is the seam it
  plugs into later.

## Out of scope

- CCAPI (above).
- Replacing the server-brokered `/api/event/station/*` board; it becomes a mirror.
- Web — the whole pipeline is `!kIsWeb`, matching the existing `LocalKioskStore` guard.
- Backend work. Phase 2 assumes `/api/event/by-code/:code` grows the new flags; until it does,
  the local override carries the event.
