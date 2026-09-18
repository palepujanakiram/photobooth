# Auto print and import thumbnails

Two event-pipeline changes made 2026-09-18, both with a backend gap behind them. Recorded
because the *reasons* are not visible from the code alone, and one of them is meant to be
deleted later.

See also [dnp-print-timing.md](dnp-print-timing.md) for the print-path work done alongside.

---

## 1. Auto print had no control anywhere

### What was wrong

`autoPrint` was honoured correctly all along — `EventPipelineSettings.resolveSteps()`
adds `EventPipelineStep.print` only when it is true, and `EventPipelineConfig` resolved it
from the backend. The settings screen displayed it. Nothing was broken in the app.

The problem was upstream: **nothing can set it.**

- `events.auto_print` (`zenai/shared/schema.ts`) defaults to `false`.
- `GET /api/events/by-code/:code/settings` returns `autoPrint: event.autoPrint === true`,
  so an explicit `false` — not a null that could fall through to
  `EventPipelineDefaults.printerEnabled`.
- `PATCH /api/events/:id/settings` can write it, but **no client ever calls it**: grepping
  `zenai/client/src` for `autoPrint`, `defaultCopies`, `printSize` or
  `/events/.../settings` returns nothing. The admin event form
  (`client/src/pages/admin/event-detail.tsx`) exposes only code, name, description,
  Active, Start, End, Photo mode, Output and Kiosk skin.

So every event in production had auto print off, the print step was never in a resolved
chain, and every print had to be released by hand with Reprint.

The same is true of `defaultCopies`, `printSize`, `themeId` and `frameId` — all are
columns with no admin UI. `themeId`/`frameId` being null is why
`EventPipelineDevConfig.fillMissingIdsFromCatalogue` exists.

### What was added — and when to delete it

A **device-local override for `autoPrint` only**, in `EventPipelineConfig`:

- `readAutoPrintOverride()` / `setAutoPrintOverride(bool?)`, resolving as
  **override → backend → default**.
- Null means "no local opinion", which is what makes it removable: once the admin UI
  lands, a device that was never toggled already defers to it.
- Scoped to the bound event — cleared by `clearCachedFlags()` (so Leave event drops it)
  and by `recordSyncedAt` when the synced code changes. Last weekend's "auto print on"
  must not start printing this weekend's event.
- `EventSettingsViewModel.setAutoPrint` calls `EventPipelineRunner.refreshSettings()`, so
  a running pipeline picks it up without a restart.

This is a **stopgap and deliberately contradicts spec §9**, which makes ZenAI the single
source of event settings. It exists only because ZenAI has no control at all. **Delete it**
— and return the row to read-only — when `event-detail.tsx` grows an event-settings
section wired to the `PATCH` endpoint that already exists. The TODO is on
`EventPipelineConfig.readAutoPrintOverride`.

### Worth knowing

Chains are frozen per item at queue time (spec §2.2), so toggling auto print affects
**photos queued from now on**: turning it on does not print the backlog, turning it off
does not cancel queued prints. The settings row says so, because an operator who expects
otherwise ends up standing at a silent printer.

### Other API gaps found, not fixed

- `EventPipelineDefaults.printerEnabled` and `printSize` are **never populated**. All four
  construction sites pass only `photoMode` and `frameCount`, so `printerEnabled` stays
  `true` regardless of the kiosk's actual setting — which `AppSettingsManager` already has
  and the guest result flow honours. Only bites when the settings endpoint fails but
  verify succeeds.
- `startsAt` / `endsAt` are returned by the settings endpoint and never parsed.
- `pipelineEnabled`, `offlineMode` and `mirrorEnabled` are parsed by `EventPipelineFlags`
  but **no ZenAI endpoint sends them**. The pipeline is reachable only because
  `EventPipelineDevConfig.forcePipelineEnabled = true` is hardcoded in shipping builds.

---

## 2. Import thumbnails were decoding the originals

### What was wrong

The import picker showed filenames only, so the first version rendered a thumbnail grid
by decoding each candidate through the `event_downscale` channel. On the Amlogic box the
picker crawled with spinners on every tile.

Two causes:

- Card items are MediaStore `content://` URIs
  (`EventStorageMethodChannel.kt`), and **Android already keeps a thumbnail cache for
  them** — but the code was fully decoding each ~6 MB original instead.
- Preview decodes ran on `EventPipelineExecutors.preview` with only 2 threads, so the
  ~60 tiles visible at once serialised two at a time.

### What was added

- `EventImageDownscaler.thumbnail` now tries `ContentResolver.loadThumbnail()` for a
  `content://`, and `ThumbnailUtils.createImageThumbnail()` (EXIF thumbnail) for a path,
  falling back to a subsampled decode only when neither has one.
- `EventPipelineExecutors.preview` widened 2 → 4 threads, matched by
  `IngestThumbnailer.maxConcurrent` — queueing more in Dart than the lane can run only
  moves the wait to the other side of the channel.

Measured on a real card: **88 of 88 hit the cache, 21ms average, ~6.5 KB each, zero
fallbacks.**

### Design constraints worth preserving

`IngestThumbnailer` previews work that has **not yet been done**, so it must not affect
the pipeline:

- Its own native lane, never `EventPipelineExecutors.import` — a picker being scrolled
  must not queue behind or compete with a running import.
- **No `withBitmapMemory` permit.** A 256px subsampled decode is ~0.3 MB; the large-bitmap
  guard exists for the ~96 MB full-resolution case and would make previews wait on a
  permit they do not need.
- Nothing is written to the ledger or disk, and a thumbnail that fails to decode is cached
  as null so a corrupt file is not retried on every scroll past. The candidate still
  imports normally.
