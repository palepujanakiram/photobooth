# Event pipeline — build plan

> **Read this with `docs/event-operator-screens-spec.md`.** That spec is the
> authority on what the screens do and why; this plan is the order to build them
> in, what to remove first, and what is already done.
>
> Written to be picked up by a session with no prior context. Everything needed
> is either here or in the two specs it references.

Branch: **`event-offline-pipeline`** (off `origin/main`). `main` untouched.

---

## 1. What already exists and is verified on hardware

Do not rebuild any of this. It works, and most of it has been run against a real
Canon card on a real device.

### Verified on device (OnePlus Nord CE, Android 13, Canon EOS card)

| Thing | Evidence |
|---|---|
| MediaStore enumeration | Real cursor returns `_size`, `date_modified`, `datetaken`, `relative_path`; Canon `CANONMSC` sidecars not indexed |
| `READ_MEDIA_IMAGES` | Granted at runtime; queries return rows |
| Card auto-detect | Mount broadcast reached Dart and triggered a scan unprompted |
| Dedupe | Rescan of an imported card reports "Nothing new" |
| Native downscale | 7.2 MB → 571 KB, 2880×1920, valid JPEG |
| **EXIF orientation** | Portrait shots (`orientation=270`) produced 1920×2880 — correctly rotated |
| Native frame composite | Portrait frame → 1240×1920 print, artwork edge to edge |
| DB coexistence | `evp_*` and `sessions`/`payments`/`outbox` in one file, kiosk rows intact |
| Print queue defer | Jobs PENDING at 0 attempts with no printer — not burning retries |
| Native lanes | `evp-io-1`, `evp-import-1`, `evp-frame-1` confirmed running |

### Built, not yet run on device

- `EventPipelineService` foreground service and the bitmap permit
- The queue screen (superseded by Phase 5 below, but the ledger reads work)

### Code that stays

```
lib/models/event_pipeline/          flags, settings, media_item, rendition,
                                    pipeline_job, event_frame, print_size,
                                    printer_consumables
lib/services/event_pipeline/        db, ledger, queue, worker, runner, stats,
                                    media_store, frame_cache, frame_compositor,
                                    ai/frame/print workers, mirror,
                                    printer_status_reader, service_channel
lib/services/event_pipeline/ingest/ ingest_source, ingest_diff, folder source,
                                    media_store source, downscaler, worker,
                                    storage/card-detect channels
android/.../eventpipeline/          storage, downscaler, compositor,
                                    card-detect, executors, service
```

~340 passing tests under `test/{models,services,screens}/event_pipeline/`.

---

## 2. Phase 0 — Remove yesterday's scaffolding

**Do this first.** Several things were built before the hub design existed and
are now either dead or actively in the way. Removing them first means later
phases are not built on top of things that are about to go.

### 0.1 Restore the three existing station views

`EventPipelineStatusStrip` was added to Capture, Theme and Print. The hub now
owns that job, and the spec says the old screens stay **exactly as they were**.

- Revert the strip and its import from
  `event_capture_station_view.dart`, `event_theme_station_view.dart`,
  `event_print_station_view.dart` (4 lines each)

### 0.2 Restore the station picker

The hub replaces the picker outright when the flag is on, so the picker does not
need an SD import card, and the scroll rework only existed to fit it.

- Revert `event_station_picker_view.dart` to its `origin/main` state — removes
  `_SdImportChoice`, the `FutureBuilder`, the `SingleChildScrollView` and the
  `EventPipelineConfig` import (~53 lines)

### 0.3 Remove settings from Kiosk settings

Event settings move to their own screen reached from the hub (spec §9).

- Revert the `EventPipelineSettingsPanel` insertion and import from
  `app_splash_screen_body.dart` (6 lines)
- Delete `lib/screens/event_pipeline/event_pipeline_settings_panel.dart` and
  `event_pipeline_settings_rows.dart`
- Keep `EventPipelineChainPreview.describe()` — Phase 7 reuses it. Move it into
  the new settings screen's widgets rather than deleting it

### 0.4 Drop the `sdImport` station role

The hub is the entry point; there is no longer a role to pick.

- Revert `event_station_role.dart` to `origin/main`, removing
  `EventStationRole.sdImport`, `EventPostSplashRoute.sdImport` and their cases
- **Keep `stationRequiresWan` and the `pipelineEnabled` parameter** — Phase 3
  needs them to route an offline event to the hub
- Update `station_routing_and_stats_test.dart` accordingly

### 0.5 Remove the local override layer

Settings are sync-only (spec §9). The override layer is now wrong, not merely
unused: it would let a device disagree with the backend.

- `event_pipeline_config.dart`: delete every `get*Override` / `set*Override` and
  `clearOverrides`; keep `cacheFlags` / `readCachedFlags` and `resolve`
- `resolve()` becomes **cached flags → defaults**, no override layer
- Prune `event_pipeline_config_test.dart` to match

> **Testing note:** with overrides gone there is no way to configure a device by
> hand. Until the backend carries `themeId` / `frameId` (§6), Phase 2 adds a
> single clearly-marked dev constant — not a settings UI.

### 0.6 Retire "Run now"

Spec §7 replaces it with Pause/Resume.

- Remove `runNow()` from `event_queue_viewmodel.dart` and its button
- Keep `EventPipelineRunner.drainAll()` — Pause/Resume and tests still use it

**Phase 0 done when:** `git diff origin/main -- ':!*event_pipeline*' ':!docs/*'`
shows only `MainActivity.kt`, `AndroidManifest.xml`, `app_routes.dart`,
`constants.dart`, `app_strings.dart`, `local_kiosk_store.dart` (the
`kKioskDirName` export), `app_splash_screen.dart` (routing), and `pubspec.*`.
Full suite green.

---

## 3. Phase 1 — Fix the card-removal data loss

**A live bug in code that already runs.** Spec §9A has the full analysis.

Pull a card mid-import and every remaining photo gets a `FAILED` row with no
image. `knownSourceRefs` matches on **all rows regardless of stage**, so a rescan
reports "0 new · N already imported" and those photographs become unreachable
while the screen reports success.

### Changes

`lib/services/event_pipeline/ingest/ingest_worker.dart`

1. Classify the error. A source-unavailable failure (`PlatformException`,
   volume-not-found, missing URI) is **not** the photo's fault.
2. On source-unavailable, **delete the ledger row** rather than
   `setStage(FAILED)`. Add `EventPipelineLedger.deleteItem(id)`.
3. Keep `FAILED` for a genuine decode failure — that is a real fault and should
   stay visible.
4. Return a distinct outcome so `import()` can stop the loop rather than
   grinding through 350 doomed items.
5. Wire the card-detect unmount stream into the existing `shouldContinue` hook so
   removal stops cleanly with `stopReason: 'Card removed'`.

### Tests

- Card vanishes mid-import → remaining rows **absent**, not `FAILED`
- Rescan after removal finds them **new again**
- A genuinely undecodable photo still lands `FAILED`
- Import stops on the removal signal instead of failing every remaining item

---

## 4. Phase 2 — Config becomes sync-only

Spec §9. Backing work for the hub.

1. `EventPipelineFlags` gains `themeId`, `frameId`, `printSize`, `defaultCopies`
   parsing (already present) — verify against §6's field list
2. `EventPipelineConfig.resolve()` = cached flags → defaults
3. Add `syncedAtMs` to the cache so the hub and settings can show "synced 09:12"
4. Add `EventPipelineSync` — fetch `/api/event/by-code/:code`, cache flags, then
   `EventFrameCache.refresh()`; report a status the hub can render
5. **Dev constants** for `themeId` / `frameId` until the backend carries them,
   behind one obviously-named constant with a `TODO` naming §6

### Tests

Sync success, sync failure with cache, sync failure without cache, and
`hasSyncedOnce` gating (Phase 3 uses it to block import).

---

## 5. Phase 3 — Event hub

Spec §3A and §4. **The new entry point.**

- `lib/screens/event_pipeline/event_hub_view.dart` + viewmodel
- Route constant; `resolveEventPostSplashRoute` returns the hub when
  `pipelineEnabled` (this is why 0.4 keeps `stationRequiresWan`)
- Readiness block: camera, printer, frames, AI, storage — each with green/amber/
  red and a tappable explanation
- Counters from `EventPipelineStats`, tapping opens the queue filtered
- **Import and Capture disabled until synced**, reason on the button
- `synced 09:12` with tap to re-sync
- Starts `EventPipelineRunner.ensureStarted()`

### Tests

Each readiness state; import blocked before sync; counters; routing with the
flag on and off (**the flag-off path must stay byte-identical** — that is the
regression guard).

---

## 6. Phase 4 — Import with volume picker

Spec §5. Rework of the existing ingest screen.

- New first state: list mounted volumes, label and size, **no auto-scan**
- Shown even for one card
- After selection, the existing scan → review → import flow
- Thumbnails in the review list (Phase 5's thumbnail rendition; until then,
  names only rather than decoding originals)
- Removal handling from Phase 1 surfaces here

---

## 7. Phase 5 — Queue rework

Spec §7. The screen most able to make the Amlogic box feel stuck.

1. **Thumbnail rendition** (`RenditionKind.thumb`, ~320 px short side).
   **Emitted from the decode that already happens** — the downscaler holds the
   bitmap, the compositor holds the canvas; each returns two encodes from one
   decode. Overwritten as stages complete so the grid shows current state.
2. **Pagination**, ~60 per page, load-more on scroll
3. **Selection mode**: Select → tick → act. `All` / `None` within the filter.
   Actions appear only when valid for the selection
4. **Pause/Resume** replacing Run now, with a live processing indicator. Pause is
   queue state and survives a restart
5. **Scope every read to `event_id`** (spec §9B) — including the counters

### Tests

Thumbnail produced and overwritten per stage; pagination; actions apply only to
selection; pause survives restart; **another event's photos never appear**.

---

## 8. Phase 6 — Item detail

Spec §8. Tap any tile.

- Three renditions side by side with dimensions
- Stage, frozen chain, **the real error text**, source card, shot time
- Retry · Skip AI · **Reprint** · Remove
- Reprint = another copy of the finished output (framed → ai → source); it does
  **not** re-run a stage

---

## 9. Phase 7 — Event settings (read-only)

Spec §9.

- Read-only list, `Sync` the only control
- **One subtitle per setting** saying what it does — read under time pressure by
  someone who did not configure the event
- Frame row shows cache state and downloads on demand (fixes the hub's warning)
- Resolved chain preview at the bottom (reuse `EventPipelineChainPreview`)

---

## 10. Phase 8 — Capture

Spec §6. Last, because it is the only phase needing camera hardware.

- Tethered EDSDK / Direct PTP via the existing stacks
- Shutter → **Confirm / Retake**; Confirm registers **and queues** into the same
  queue as card imports; Retake writes nothing
- Recent strip of the last few shots, so a photographer can see frames landing
- CCAPI plugs in here later with no screen change

---

## 11. Device and environment notes

The test device silently disables two things, and both look like app bugs:

- **OTG** (`persist.sys.oplus.otg_support=0`) — the USB bus goes completely
  empty. Check `/sys/bus/usb/devices/` before suspecting the ingest code.
  Re-enable: Settings → Additional settings → OTG connection
- **Wireless debugging** — ports refuse while the device still answers ping.
  Find it with `adb mdns services`, never a port scan

A long rebuild is usually enough for OTG to drop, so re-check
`sm list-volumes all` after every build.

Run the app with:
`flutter run --debug --no-enable-impeller -d <ip:port>` from `photobooth/`.

---

## 12. Backend dependency

**`themeId` and `frameId` on `/api/event/by-code/:code` are the blocker** for
running an AI or frame event on real config. Full field list in spec §12.
Everything else has a sane default; a list of frame ids does not tell the device
which one to composite.

Until they land, Phase 2's dev constants carry it.

---

## 13. Deliberately not in this plan

- **Guest-facing screens** — operator only for this phase
- **CCAPI** — plugs into Phase 8 later
- **Multi-device queue** — separate document; the venue link is too slow for a
  cloud-brokered board, so device-to-device on the venue LAN is the direction
- **Pre/post event flows and local cleanup** — spec §9C. `event_id` on every row
  keeps a per-event purge a single delete
- **Deleting the old event screens** — not until the new flow has run a real
  event
- **Orchestration off the UI isolate** — the foreground service removed the
  stall; CPU contention with rendering remains, worth revisiting after Phase 5
  shows how the box actually behaves
