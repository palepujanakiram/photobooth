# Direct PTP DSLR — native capture screen

**Branch:** `Direct-PTP-Native-Camera` (from `main` @ `05f0680`)
**Target hardware:** the Android TV box (RTC Mini PC, Android 11 / SDK 30, `armeabi-v7a`,
3.58 GB RAM, 256 MB heap) + Canon EOS 200D II over USB. **Not** a phone-only build — the
final implementation has to run on the box.

## 0. Working rule — the POC is read-only

**`android-camera-connection` (the Canon tether app) is never modified.** Not a package
rename, not a refactor, not a "small fix while we're in there". Every change on this work
lands inside `photobooth/`.

Its code is **copied** into the photobooth app and adapted there. The POC stays exactly as
it is on disk, which is what makes it useful:

- It remains a **known-good reference** to diff against when the photobooth copy misbehaves
  on hardware — a standalone app that provably drives this camera is the fastest way to
  answer "is it the protocol or is it our integration?"
- It remains **independently runnable** on the box, so the camera can be exercised without
  building the whole Flutter app.
- Its `docs/` (`STATUS.md`, `GAPS_AND_EDGE_CASES.md`, `DEBUGGING.md`, the device-capability
  dump) stay the authoritative record of what was learned on hardware.

Consequence for this plan: the two copies **will** drift, and that is accepted rather than
fought. The photobooth copy is the one that ships; the POC is a frozen reference. If a bug
is found in the photobooth copy that also exists in the POC, it is fixed in photobooth only
and noted here.

---

## 1. Where the app is today

`photo_capture` can already draw its still from three places, chosen at runtime:

| Source | How | Where |
|---|---|---|
| **Device camera** | `camera` plugin → CameraX | `photo_capture_viewmodel.dart` `_openFreshCameraController` |
| **UVC / HDMI capture card** | `uvccamera` plugin | `photo_capture_uvc_screen.dart` |
| **Pi sidecar** | HTTP → Raspberry Pi → `gphoto2` → USB → Canon | `local_camera_service.dart` |

For this work the device camera is the baseline being replaced: today the box shoots with
whatever camera Android exposes, and we want it shooting with the DSLR instead.

Every DSLR path in the app goes through the Pi. That costs a second computer, a LAN and a
second thing to power and debug at every event, and it caps the still at a re-encoded
1920 px JPEG (`kSidecarCaptureMaxLongEdge`), because the Pi does the downscale before the
app ever sees the image.

The `android-camera-connection` POC removed that dependency: pure Kotlin PTP over
`UsbDeviceConnection`, no NDK, no Pi. On the target box it measured:

- Live view **18.4–20.9 fps, 0 dropped frames**, sustained
- Capture **274 ms median** for ~6.5 MB (≈24 MB/s), 11/11 successful
- 6000×4000 originals verified byte-exact on disk
- Camera + printer + touch panel + wireless receiver coexisting through one chained hub
- 206 unit tests

Everything below is about copying that stack into this app (§0 — the POC itself stays
untouched).

---

## 2. The shape of the integration

**Decision taken (yours): the capture screen is real native Kotlin**, launched from Flutter
and returning finished stills. Not a Flutter screen with a native texture.

```
Flutter                                    │  Native (Kotlin)
                                           │
theme_selection → frame_select             │
        │                                  │
        ▼                                  │
photo_capture_view.dart                    │
  (direct_ptp branch: no CameraX,          │
   no preview, just a launcher)            │
        │                                  │
        │  MethodChannel .runCaptureSession(args)
        ├──────────────────────────────────►  CanonCaptureActivity
        │                                  │    ├─ live view surface (EVF frames)
        │                                  │    ├─ countdown + shutter
        │                                  │    ├─ Classic 4-shot loop + thumbs
        │                                  │    └─ download → disk
        │                                  │              │
        │  ◄───────────────────────────────┼──────────────┘
        │   { status, shots:[{originalPath, displayPath, …}] }
        ▼                                  │
photo_generate → review → result → print   │
```

Only **file paths** cross the channel. A 6000×4000 JPEG is ~96 MB decoded — it must never
become a Dart `Uint8List` or a Flutter `ui.Image` on a 256 MB heap.

### 2.1 What "native screen" actually costs, and the boundary that keeps it small

Worth being straight about: `photo_capture_view.dart` is 5,435 lines and
`photo_capture_viewmodel.dart` is 3,620. Naively "porting the capture screen" is a rewrite
with two implementations to keep in step forever.

It is much smaller than that here, because **most of that code exists to work around
CameraX, UVC and HDMI capture cards — and direct PTP deletes the problems, not just the
code.**

| Flutter code | Fate under direct PTP |
|---|---|
| `photo_capture_uvc_*.dart` (7 files) | **Not ported.** No UVC device in this path. |
| `photo_capture_hdmi_pose_helpers.dart` | **Not ported.** No capture card. |
| `photo_capture_preview_rotation.dart`, `_view_aspect.dart`, capture-card aspect lock | **Not ported.** Preview and still come from the same sensor, through the same PTP session. The entire "live feed and still disagree about orientation" problem class does not exist. |
| `photo_capture_camera_picker_screen.dart`, CameraX recovery, `_captureSingleFrameFallback` | **Not ported.** One camera, found by USB enumeration. |
| `photo_capture_sidecar_helpers.dart` | **Not ported.** No Pi. |
| `photo_capture_normalize_helpers.dart` / `_preprocess_helpers.dart` | **Native equivalent.** Kotlin `ExifInterface` + subsampled decode; cheaper than the Dart `compute()` isolate that currently blows the 20 s normalize budget on multi-MP stills. |
| **Countdown timing** (10 s pose / 8 s rearrange) | **Ported.** Values passed in from Dart, so `AppConstants` stays the single source. |
| **Classic 4-shot loop + strip thumbs** | **Ported.** This is the real one — genuinely new Kotlin. |
| **Idle / abandon timeout** | **Ported** as a session timeout that returns `cancelled`. |
| Branding, copy, colours | **Passed in as arguments.** `AppStrings` / theme stay in Dart; the native screen renders what it is handed. Nothing is duplicated. |
| Upload prep, face count, gallery handlers, `PhotoModel` | **Stay in Flutter**, unchanged, fed from the returned paths. |

So the native surface is: a live-view view, a countdown, a shot loop, a thumb strip, a
timeout, and a result contract. That is a screen, not a subsystem.

### 2.2 Activity, not PlatformView

Launch `CanonCaptureActivity` on top of `MainActivity` and return a result. **Not** an
`AndroidView` / hybrid-composition PlatformView embedded in the Flutter route.

Reasons, in order of weight on this hardware:

1. **Hybrid composition copies every frame through Flutter's raster thread.** At ~20 fps of
   live view on a 32-bit box with a 256 MB heap, that is the exact per-frame cost the POC
   engineered away with `inBitmap` reuse. A separate Activity draws straight to its own
   window with zero Flutter involvement.
2. **Surface lifecycle.** A PlatformView's surface can be created, destroyed and recreated
   by Flutter's view hierarchy at moments the USB session knows nothing about. An Activity
   has one well-understood lifecycle that the camera session can bind to.
3. **It matches how this repo already does native.** `DnpUsbMethodChannel`,
   `SelphyMethodChannel`, `ReceiptUsbMethodChannel` are all `object` singletons with
   `register(engine, context)` / `onResume` / `onDestroy`, wired in
   `MainActivity.configureFlutterEngine`. The camera bridge is the same idiom plus an
   Activity.

Cost to accept: a visible Activity transition when capture starts and ends. Mitigate with
`overridePendingTransition(0, 0)` and a matching background colour so it reads as a screen
change, not an app switch.

### 2.3 Views, not Compose

The POC's UI is Jetpack Compose. **The native capture screen should be plain Android Views
(XML + `SurfaceView`), not Compose.**

This app's `:app` module is built by AGP 9's `com.android.built-in-kotlin` plugin, with
`android.builtInKotlin` deliberately left **false** globally for still-legacy transitive
plugins (see `android/build.gradle`). Adding the Compose compiler plugin into that
arrangement is a toolchain fight with no product value: the POC's Compose UI is a
developer control panel we are replacing wholesale anyway. A `SurfaceView`, a `TextView`
and a `LinearLayout` of thumbnails is the entire screen.

This also keeps the APK and the cold start where they are — the box already takes 8.9 s to
cold start in the POC's measurement.

---

## 3. Phases

Each is independently shippable and independently revertible. Nothing in P1–P4 changes
behaviour for any existing build: the direct-PTP path is unreachable until P5 selects it,
and the default stays `device`.

### P1 — Copy the PTP stack into photobooth, headless

Copy the POC's pure-Kotlin layers into
`photobooth/android/app/src/main/kotlin/com/srisarani/fotozenai/canon/`. **Read out of the
POC, write into photobooth — the POC tree is not touched** (§0).

| Copied from POC | Into photobooth | Lines |
|---|---|---|
| `usb/` (5 files) | `canon/usb/` | ~890 |
| `ptp/` (7 files) | `canon/ptp/` | ~1,400 |
| `canon/` (7 files) | `canon/eos/` | ~1,650 |
| `capture/` (3 files) | `canon/capture/` | ~420 |
| `session/CameraSessionManager.kt`, `state/ConnectionState.kt` | `canon/session/` | ~610 |

Mechanical changes, all applied **to the photobooth copy only**:

- Package rename `com.managemyfloor.canontether.*` → `com.srisarani.fotozenai.canon.*`
- **Timber → a `CanonLog` shim** over `android.util.Log`. The POC uses Timber throughout;
  this app does not have it, and adding a logging dependency for a find-and-replace is not
  worth it. One small file, one mechanical substitution.
- Copy the POC's 206 unit tests into `photobooth/android/app/src/test/` and rename their
  packages to match.

Nothing above is a change to `android-camera-connection`; it keeps its own package names,
its own Timber dependency and its own passing test suite.

Build changes required (this module has **no** Kotlin unit tests and **no** declared
coroutines dependency today — both are new):

```groovy
// android/app/build.gradle
android {
    testOptions {
        unitTests {
            includeAndroidResources true
            returnDefaultValues true
        }
    }
}
dependencies {
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:<match Kotlin 2.3.20>'
    implementation 'androidx.exifinterface:exifinterface:1.3.7'

    testImplementation 'junit:junit:4.13.2'
    testImplementation 'com.google.truth:truth:1.4.4'
    testImplementation 'org.jetbrains.kotlinx:kotlinx-coroutines-test:<same>'
    testImplementation 'org.robolectric:robolectric:4.13'
}
```

> Coroutines currently reach the app only transitively (the `minifyEnabled false` comment
> in `build.gradle` refers to R8 choking on a transitive coroutines jar). Depending on a
> transitive version for a USB protocol's threading model is not acceptable — declare it.

**Carry the hardware-earned fixes across. They are not polish** — each one cost a real
debugging session and five of the seven presented as a symptom in a different subsystem:

| ID | What it is |
|---|---|
| `C-16` | Live view must stay down until the image is **downloaded**, not just shot — a timer-based resume starves the download into a self-reinforcing busy deadlock |
| `C-17` | Force drive mode to single, or the body's own self-timer adds its own countdown on top of ours |
| `C-19` | Route EVF to `TFT+PC` (§5). PC-only blanks the body's screen to "Busy" and cuts live-view stability ~8× (~54 frames per start vs ~430) |
| `P-15` / `P-16` | Capacity is an **operation** (`0x911A`), not a property, and destination must be set **before** it — reverse the order and the camera silently saves to its card while the host waits forever |
| `P-17` | This body emits `ObjectAddedEx64` (`0xC1A9`), not `0xC181`, with no filename |
| `P-18` | The camera stays `DeviceBusy` up to ~8 s after a shot; the retry budget must cover it |
| `P-19` | The whole settings state arrives in the **first** `GetEvent` — the event flow needs `replay`, or a late subscriber sees an empty camera |
| `P-20` | `BatteryPower` is an enum, not a percentage |
| `P-21` | Canon `0xA102 NotReady` is transient — treat it like `DeviceBusy` |
| `U-06` | `CLEAR_FEATURE(ENDPOINT_HALT)` on connect — recovers a wedged camera without a power cycle, which on a kiosk is the difference between a log line and a site visit |
| `U-17` | Drain budget must exceed a live-view frame, or an unclean exit needs a replug |

**Done when:** `./gradlew :app:testDebugUnitTest` passes in `photobooth/android/`, and
`./scripts/flutter_with_version.sh build apk` still builds. No Dart touched, and
`git status` in `android-camera-connection` is clean.

### P2 — Bridge and connection lifecycle, no UI

`CanonPtpMethodChannel.kt` on `com.srisarani.fotozenai/canon_ptp`, following the
`DnpUsbMethodChannel` idiom exactly, registered in `MainActivity`:

| Method | Returns |
|---|---|
| `hasUsbHost` | `bool` |
| `probeDevice` | `{vendorId, productId, manufacturer, product}` or `null` |
| `requestPermission` | `bool` |
| `connect` | `{connected, model, firmware, serial}` |
| `status` | `{state, batteryLabel, shotsRemaining, liveViewRunning}` |
| `disconnect` | `void` |

Plus `com.srisarani.fotozenai/canon_ptp_status` as an `EventChannel` mirroring
`CameraSessionManager.state` so Flutter can show connection state without polling.

Manifest additions:

- `res/xml/canon_device_filter.xml` — vendor `1193` (**decimal**; Android's `usb-device`
  attributes are decimal and hex silently never matches) plus a class 6 / subclass 1 /
  protocol 1 entry that matches any PTP camera.
- The `USB_DEVICE_ATTACHED` filter already exists on `MainActivity` for the printer; the
  camera filter joins the same `meta-data` resource list.

`CameraSessionManager` is already a process-wide `object` owning one USB thread, which is
exactly what an Activity-scoped bridge needs.

**Done when:** with the DSLR plugged into the box, a debug call from Dart returns the model
name and the capability dump lands in the app's files dir.

### P3 — `CanonCaptureActivity`, single shot

The native screen, minimum viable:

- `SurfaceView` full-screen, `CameraSessionManager.liveView` frames decoded into a reused
  `Bitmap` (`inBitmap`, RGB_565) and blitted to the surface. This is the POC's live-view
  loop with a different sink.
- A shutter path: stop live view → release → wait for `ObjectAddedEx64` → `GetPartialObject`
  download → write original to app files dir → produce a ~1920 px display derivative by
  **subsampled** decode (`inSampleSize`), never a full decode.
- Returns `{status: 'completed', shots: [{originalPath, displayPath, widthPx, heightPx,
  bytes, capturedAtMs}]}`.

Two things must be right on the box specifically:

- **Orientation.** The box drives a 1920×1080 panel rotated to portrait (`init=1920x1080`,
  `cur=1080x1920`). The POC left this open. `CanonCaptureActivity` must declare the same
  orientation as `MainActivity` and lock it, or the first frame lands sideways.
- **Input-agnostic.** The box reports `touch=true dpad=true leanback=true`. Any control
  (cancel, retake) needs a visible focus ring and D-pad reachability, not just a tap target.

**Done when:** one press produces a 6000×4000 JPEG on disk and its path is back in Dart,
running on the box.

### P4 — Countdown, Classic 4-shot, timeout, branding

Everything that makes it a booth screen rather than a shutter button:

- Countdown with the existing values passed in (`10 s` pose,
  `AppConstants.kFlashbackBetweenShotRearrangeDuration` = 8 s between shots) — Dart stays
  the source of truth for timing.
- Classic loop: `shotCount` shots, thumb strip filling as it goes, rearrange copy between
  shots (`AppStrings.flashbackRearrangeForShot`, passed in).
- Capture sound, played natively so it lands on the shutter and not a channel round-trip
  later.
- Session timeout → `{status: 'cancelled', reason: 'idle'}`, so a walk-away cannot strand
  the booth in a native Activity.
- Error contract: `{status: 'error', code, message}` with codes distinct enough to act on —
  `no_device`, `permission_denied`, `connect_failed`, `capture_failed`, `download_failed`,
  `camera_busy`, `card_unavailable`.

`card_unavailable` exists because `CaptureDestination = BOTH` (§5) makes a missing or full
SD card a capture failure. It needs its own code: "put a card in the camera" is an
operator action, and burying it inside `capture_failed` turns a ten-second fix into a
debugging session.

**Done when:** a full Classic 4-shot session runs on the box start to finish and hands four
paths back.

### P5 — Flutter integration and source selection

New `lib/utils/camera_source_config.dart` mirroring the existing `CameraSidecarConfig` /
`printerTransport` shape:

```dart
enum CameraSource { device, uvc, sidecar, directPtp }
// --dart-define=CAMERA_SOURCE=direct_ptp
// default: device — existing builds are byte-identical in behaviour
```

New `lib/services/direct_ptp_camera_service.dart` — a thin, fully testable wrapper over the
method channel (no UI, no platform types leaking), unit tested against a fake channel
handler as `CLAUDE.md` requires.

Wiring, at three seams:

1. `photo_capture_view.dart` — when the source is `directPtp`, skip camera init entirely and
   run the native session; render a plain branded scaffold while the native Activity is up.
2. `photo_capture_viewmodel.dart` — accept externally-produced `XFile`s into
   `_assignCapturedPhotoModel` with `cameraIdOverride: 'ptp:EOS200DII'`, reusing the existing
   `skipCapturedImagePixelSizeDecode` escape hatch so a 24 MP still is never decoded in Dart.
3. `fotoflashback_capture_viewmodel.dart` — accept the four returned shots directly rather
   than one at a time.

**Both sidecar and device-camera paths remain fully intact and reachable.** Nothing is
deleted on this branch.

**Done when:** `--dart-define=CAMERA_SOURCE=direct_ptp` gives a complete AI single-shot run
and a complete Classic 4-shot run through to print, and without the define the app behaves
exactly as `main`.

### P6 — Validation on the box

Camera on the **`ACK-E18` AC coupler** — sustained tethering flattened the battery twice
during POC work, and USB drops when it browns out. Printer and camera on the powered hub
together, as at an event.

1. 20 consecutive captures, no dropped session
2. Live view sustained 10 minutes; frame rate and dropped count logged
3. Full Classic 4-shot → strip → DNP print
4. Unplug the camera mid-session; confirm recovery without an app restart
5. Peak heap during capture + print, measured — see §4
6. **Pull the SD card and confirm the JPEGs are physically on it**, matching the host copies
   one for one (§5). Then run once with the card removed and confirm the failure surfaces as
   `card_unavailable` rather than a hang or a generic capture error.
7. Disconnect cleanly and confirm the camera is left on `CAMERA_CARD` with `EVFOutputDevice
   = OFF` — i.e. it still shoots normally standalone without a power cycle.
8. **With live view running, confirm the camera's own rear screen shows a live viewfinder,
   not "Busy"** (§5). If it shows Busy, EVF routing has regressed to PC-only — check that
   before anything else, because it also costs ~8× the stream stability.
9. Record the SD card model alongside the post-capture busy timings, since `BOTH` puts the
   card write inside that window.

---

## 4. Risks, with what we do about each

| Risk | Handling |
|---|---|
| **Heap.** `<application>` has **no `largeHeap`**. The box gives 256 MB standard / 384 MB with it. The POC measured 66 MB peak for a full print from a 24 MP original — but that was a lean Compose app, not this one, which carries a Dart heap, image caches and a `low_memory_monitor.dart` that exists because memory is already tight. | Measure at P3 before deciding. `largeHeap` is available but it is a blunt instrument that also delays GC; the first lever is keeping every full-res decode subsampled and in Kotlin. **Decision deferred to P3 with a measurement behind it.** |
| **A 6000×4000 original in the wrong place is an instant OOM.** | Paths across the channel, never bytes. All full-res decoding stays in Kotlin with `inSampleSize`. Enforced by the method-channel contract, not by convention. |
| **Camera and printer share one USB hub.** Verified coexisting, but a print streams ~6.8 MB while live view runs. The POC saw a 38 s print transfer with live view active, cause not attributed. | Measure contention at P6. If it is real, stop live view during print — the guest is not posing then anyway. |
| **`DeviceBusy` after live view** — intermittent in the POC, possibly battery-related. | Reproduce on AC power before P3 sign-off. |
| **Activity transition visible mid-flow.** | Zero-duration transitions and a matching background. Verify on the box — a TV box compositor can behave differently from a phone. |
| **Two capture UIs to maintain** (Flutter for device/UVC/sidecar, native for PTP). | Real and unavoidable given the native-screen decision. Contained by §2.1's boundary and by keeping all timing values, copy and colours in Dart so only *behaviour* is duplicated, never content. |
| **Toolchain.** AGP 9 built-in Kotlin, `builtInKotlin=false` globally, `minifyEnabled false` for an R8/coroutines crash. | Views not Compose (§2.3); declare coroutines explicitly; add the test config as a separate first commit so a build break is trivially bisectable. |
| Quality gates — Sonar >90 % on new code, 100 % on services/utils/models, S107 (≤7 params), S3776 (complexity ≤15) | The Kotlin arrives already tested (206 tests). Budget Dart test work for `DirectPtpCameraService` and `CameraSourceConfig`. The launch arguments will exceed 7 params — use a `DirectPtpCaptureRequest` input class from the start. |

## 5. Decisions and open questions

### Locked: `CaptureDestination = BOTH`

Every capture writes to **both** the camera's SD card and the host.

```kotlin
EosCaptureDestination.BOTH  // CAMERA_CARD (2) or HOST (4) = 6
```

The card keeps the original as an archive while the host still receives every frame over
USB. `HOST` alone means exactly one copy of a photo that cannot be reshot, living in
app-scoped storage that is deleted with the app; the card costs nothing and survives a
reflash. `CAMERA_CARD` alone is not an option at all — the image never crosses USB, so
there would be nothing to build a print derivative from.

Three things this pins down for implementation:

- **Order is load-bearing.** Destination must be set **before** the `EOS_PCHDDCapacity`
  (`0x911A`) operation. Reversed, the destination write is accepted without error and then
  silently ignored: the camera saves to its card and emits `StorageInfoChanged` instead of
  `ObjectAdded`, so the host waits forever for a photo it was never offered. Nothing errors
  (`P-15`/`P-16`). The POC's `EosCaptureTest` asserts this order — keep that test.
- **A card must be present and have space.** With `BOTH`, a missing or full card is now a
  capture failure mode that `HOST`-only did not have. The pre-flight check at P2 should
  surface card state, and P4's error contract needs a `card_unavailable` code.
- **Card speed is now on the critical path.** The body writes a full 24 MP JPEG to the card
  *inside* the post-capture busy window — the same window `P-18` budgets ~10 s of
  busy-retry for. A slow card stretches it, and the symptom is the camera sitting on "Busy"
  longer than expected after a shot, which reads exactly like a protocol bug. **Use a fast
  UHS-I card and rule it out first** before debugging the busy path. Worth recording the
  card model in the P6 results so the measurement means something later.
- **Teardown restores `CAMERA_CARD`**, so the camera is left usable standalone after the
  booth closes. The POC already does this in `restoreCardCapture()`.

> **Verify on hardware at P6, do not assume.** The POC's `EosCapture.kt` already sets
> `BOTH`, but its `EosCaptureDestination` values carry a `⚠️ VERIFY against ptp.h` marker,
> and its `STATUS.md` open item #4 still claims capture is HOST-only with nothing reaching
> the card. Code and notes disagree. Either the note is stale, or the body did not honour
> `6` and fell back to host. **The P6 checklist must include physically pulling the card and
> confirming the JPEGs are on it** — "we set the property" is not evidence.

### Locked: `EVFOutputDevice = TFT + PC`

Live view is routed to the camera's own screen **and** the host, never to the host alone.

```kotlin
EvfOutputDevice.CAMERA_TFT_AND_PC  // CAMERA_TFT (1) or PC (2) = 3
```

With PC-only routing (`2`) the 200D II blanks its rear screen and displays **"Busy"** for
as long as live view runs (`C-19`). Two reasons that is unacceptable for a booth:

- **The camera stays functional.** The body keeps a working viewfinder, so an operator can
  frame, check focus and see what the camera sees without going through the app. On
  PC-only the camera is a black box with a "Busy" placard — indistinguishable from hung, so
  a guest or operator starts pressing things.
- **It is measurably more stable, not just prettier.** The POC measured **~54 frames per
  live-view start on PC-only against ~430 with TFT+PC** — roughly 8×. Whatever the body is
  doing differently, PC-only is the worse path on this hardware.

This is the same escalation `fotozen-sidecar` already applies on the Pi path
(`output=TFT + PC`), which is why the current booth does not show the symptom.

The POC already sets this (`EosLiveView.kt:203`), so the copy inherits it. It is recorded
here because it looks like a redundant setting — routing to the host *and* the screen when
only the host consumes frames reads as something to simplify away. It is not. Do not
change it to `PC` on the grounds that the camera's screen is unused.

Teardown sets `EVFOutputDevice = OFF`, and `CaptureDestination` back to `CAMERA_CARD`, so
the body is left usable standalone.

### Open

1. **`largeHeap`** — settle at P3 with a measured peak, not up front.
2. **Full-resolution print** — the app currently prints the 1920 px derivative. Holding the
   6000×4000 original means the print becomes a single high-quality 3.25× reduction from
   untouched capture data instead of a 1.04× reduction of an already-resized, already-
   recompressed image. Deliberately **out of scope here** (you scoped this round to getting
   capture working end-to-end) — the original is written to disk at P3 regardless, so the
   print change is a later, isolated commit.
3. **Deleting the sidecar** — not on this branch. `main` keeps a working fallback until
   direct PTP has run a real event.

---

## 6. Verification

**Kotlin unit** — the POC's 206 tests, copied into photobooth and run by
`./gradlew :app:testDebugUnitTest` there. They cover the parts that are pure logic and
expensive to debug on hardware: ZLP handling (mutation-verified), PTP string parsing
(mutation-verified), transaction-ID recovery, EVF frame parsing including a fuzz test,
event-loop survival under malformed payloads.

**Dart unit** — `DirectPtpCameraService` against a fake method-channel handler: session
returns paths, cancellation surfaces as cancelled, each error code maps to a typed failure,
and the 24 MP still is never decoded in Dart.

**On hardware** — §3 P6, on the box, on AC power, with the printer attached.
