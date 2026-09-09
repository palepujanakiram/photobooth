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

## 2. Start of every session

Do this **before any work**, every time — not once.

```bash
git checkout event-offline-pipeline
git pull                       # our branch, in case it moved on the remote
git fetch origin main          # refresh the origin/main ref
```

`git pull` and `git fetch origin main` are **not the same thing** and both are
needed. The first brings down anything pushed to this branch from elsewhere;
without it you commit onto a stale local branch and diverge. The second updates
the `origin/main` ref that Phase 0's restores and the back-merge both read from —
restoring "from main" against a week-old ref silently gives you week-old files.

Then merge main in — but **after** Phase 0 on the first session, and at this
point on every session after. §2.1 explains the ordering.

**Main moves fast** — 28 commits in a single day during this work. A day of drift
merges trivially; a fortnight of it does not. Merging daily is what keeps the
one-conflict experience we have had so far.

---

## 2.1 Why Phase 0 runs before the back-merge

On the **first** session only, do the removals *before* merging main.

Phase 0 shrinks our diff against main from ~11 touched files to ~6, and every
file we stop touching is a file that can never conflict again. It also
pre-resolves conflicts for free: once a file is restored to `origin/main`'s
state, git sees we did not change it, so the merge takes main's newer version
**cleanly** rather than raising a conflict.

Merging first means potentially resolving a conflict by carefully preserving code
you then delete ten minutes later. That already happened once by hand —
`event_print_station_view.dart` conflicted, and the resolution was the same as
Phase 0's removal.

**Keep them as separate commits.** If the suite goes red you want to know whether
it was our removal or main's changes; mixed into one commit you are bisecting
inside a single change.

```bash
# first session only
<Phase 0 removals>        →  commit "Remove pre-hub scaffolding"
git merge origin/main     →  commit "Merge origin/main"
flutter test              →  verify once; blame is unambiguous

# every session after
git merge origin/main     →  commit, verify, then build
```

---

## 3. Phase 0 — Remove pre-hub scaffolding

Several things were built before the hub design existed and are now either dead
or actively in the way. Removing them first means later phases are not built on
top of things that are about to go.

### 0.1–0.3 File restores — no hand editing

Five files go back to main byte for byte. Do not edit these by hand; restoring
from the ref is both safer and what makes the later merge conflict-free.

```bash
git checkout origin/main -- \
  photobooth/lib/screens/event_station/event_capture_station_view.dart \
  photobooth/lib/screens/event_station/event_theme_station_view.dart \
  photobooth/lib/screens/event_station/event_print_station_view.dart \
  photobooth/lib/screens/event_station/event_station_picker_view.dart \
  photobooth/lib/screens/splash/app_splash_screen_body.dart
```

That removes, in one step:

- **`EventPipelineStatusStrip`** from the three station views — the hub owns that
  job now, and the spec says those screens stay exactly as they were
- **`_SdImportChoice`**, its `FutureBuilder`, the `SingleChildScrollView` rework
  and the `EventPipelineConfig` import from the picker — the hub replaces the
  picker, so none of it is needed
- **`EventPipelineSettingsPanel`** from the splash body — settings move to their
  own screen

Then delete the two panel files:

```bash
git rm photobooth/lib/screens/event_pipeline/event_pipeline_settings_panel.dart \
       photobooth/lib/screens/event_pipeline/event_pipeline_settings_rows.dart
```

**Before deleting**, lift `EventPipelineChainPreview.describe()` out of
`event_pipeline_settings_rows.dart` — Phase 7 reuses it, and its tests in
`test/screens/event_pipeline/event_pipeline_settings_rows_test.dart` should move
with it rather than being lost.

### 0.3b What is intentionally kept

Event settings move to their own screen reached from the hub (spec §9).

These existing files stay modified — do **not** restore them:

| File | Keep because |
|---|---|
| `MainActivity.kt` | Registers the six native channels |
| `AndroidManifest.xml` | Foreground service + `FOREGROUND_SERVICE_DATA_SYNC` |
| `app_routes.dart` | Pipeline routes; Phase 3 adds the hub |
| `constants.dart` | Route constants |
| `app_strings.dart` | Pipeline strings |
| `local_kiosk_store.dart` | `kKioskDirName` export — without it the pipeline opens a **second database** (see §1) |
| `app_splash_screen.dart` | Pipeline-aware routing; Phase 3 points it at the hub |
| `pubspec.yaml` | `crypto` for the content key |

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

**Phase 0 done when:**

```bash
git diff origin/main --name-only -- ':!*event_pipeline*' ':!docs/*'
```

lists only the eight files in the keep table above. Then merge main (§2.1),
then run the full suite.

Expect two pre-existing failures in `test/utils/fotoflashback_payment_flow_test.dart`
— they fail on clean `main` too and are not ours. Verify against a worktree
before assuming any failure is new:

```bash
git worktree add /tmp/mainchk origin/main
cd /tmp/mainchk/photobooth && flutter test <the failing file>
git worktree remove /tmp/mainchk --force
```

---

## 4. Phase 1 — Fix the card-removal data loss

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

## 5. Phase 2 — Config becomes sync-only

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

## 6. Phase 3 — Event hub

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

## 7. Phase 4 — Import with volume picker

Spec §5. Rework of the existing ingest screen.

- New first state: list mounted volumes, label and size, **no auto-scan**
- Shown even for one card
- After selection, the existing scan → review → import flow
- Thumbnails in the review list (Phase 5's thumbnail rendition; until then,
  names only rather than decoding originals)
- Removal handling from Phase 1 surfaces here

---

## 8. Phase 5 — Queue rework

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

## 9. Phase 6 — Item detail

Spec §8. Tap any tile.

- Three renditions side by side with dimensions
- Stage, frozen chain, **the real error text**, source card, shot time
- Retry · Skip AI · **Reprint** · Remove
- Reprint = another copy of the finished output (framed → ai → source); it does
  **not** re-run a stage

---

## 10. Phase 7 — Event settings (read-only)

Spec §9.

- Read-only list, `Sync` the only control
- **One subtitle per setting** saying what it does — read under time pressure by
  someone who did not configure the event
- Frame row shows cache state and downloads on demand (fixes the hub's warning)
- Resolved chain preview at the bottom (reuse `EventPipelineChainPreview`)

---

## 11. Phase 8 — Capture

Spec §6. Last, because it is the only phase needing camera hardware.

- Tethered EDSDK / Direct PTP via the existing stacks
- Shutter → **Confirm / Retake**; Confirm registers **and queues** into the same
  queue as card imports; Retake writes nothing
- Recent strip of the last few shots, so a photographer can see frames landing
- CCAPI plugs in here later with no screen change

---

## 12. Device and environment notes

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

## 13. Backend dependency

**`themeId` and `frameId` on `/api/event/by-code/:code` are the blocker** for
running an AI or frame event on real config. Full field list in spec §12.
Everything else has a sane default; a list of frame ids does not tell the device
which one to composite.

Until they land, Phase 2's dev constants carry it.

---

## 14. Deliberately not in this plan

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
