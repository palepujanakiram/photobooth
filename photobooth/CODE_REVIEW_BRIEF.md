# Photobooth — Architectural Cleanup Brief

Living status of the architectural review. Items keep their original numbering so history is traceable; this file is the source of truth for what's open.

---

## ✅ Completed

- **P0.1 — Customer-session chokepoint (code-driven exits).** `endPhotoboothCustomerSession()` + `endPhotoboothCustomerSessionLogged(context)` in `lib/services/customer_session_lifecycle.dart`. Six call sites await it: ThankYou exit, Splash ×3, ResultViewModel ×2. `SessionManager.endCustomerSession()` always persists removal even when memory is null.
- **P0.2 — FCM cross-customer state cleared.** `PaymentPushCoordinator.resetForNextCustomer()` is `async`, clears `_lastHandledPaymentId`, in-memory queue, and calls `FcmPaymentPendingStore.clear()` to wipe the disk-persisted background payload.
- **P1.1 (partial) — Type-safe route args.** `ThemeSelectionArgs`, `GenerateArgs`, `ResultArgs`, `QrShareArgs`, `ThankYouArgs` use `switch` promotion / `is` guards — no unchecked casts. Map-shaped inputs with bad types now return `null` instead of throwing. *Still open:* `FrameSelectArgs` and a `CaptureResult` type — see P1.1 below.
- **P1.2 — Tightened route-args tests.** `test/route_args_test.dart` covers wrong-type, partial-map, junk-list-element negative paths.
- **P2.4 (partial) — `print()` removed.** `dart analyze lib/` is clean for `avoid_print`. *Still open:* Bugsnag throttling on polling endpoints.
- **Test coverage on the chokepoint.** `test/customer_session_lifecycle_test.dart` covers back-to-back sessions, stale-prefs regression, and the disk-persisted FCM payload clear.

---

## P0 — Kiosk safety (still open)

### P0.1 (remainder) — Time- and user-driven session resets
The chokepoint exists; the calls into it from non-code-driven exits do not. These are the operationally riskiest gaps right now.

- **`KioskIdleWatcher`** — single owner in `KioskManager` (or new file). Listens for taps/key events globally; after N sec of inactivity (start with 90s), calls `endPhotoboothCustomerSessionLogged('idle: timeout')` and routes to slideshow. Without this, a customer who walks away mid-flow leaks to the next.
- **`didChangeAppLifecycleState` abandonment check.** In `_PhotoBoothAppState`, on resume, if `now - pausedAt > kSessionExpiryGrace` (5 min), call the chokepoint. Single-file change.
- **Splash cold-start expired-session path.** When `SessionManager.restore()` finds expired prefs, route through the chokepoint so the FCM store is cleared symmetrically.

**Done when:** Manual test — start a flow, lock the kiosk, return after the threshold; next user sees a clean splash, no inherited session, no FCM replay.

---

### P0.3 — `BaseViewModel` with safe-notify + cancellation
**Problem:** `ResultViewModel` defends notify-after-dispose with a `_disposed` flag (`lib/screens/result/result_viewmodel.dart:1338-1349`); other VMs don't. `CaptureViewModel`'s `notifyListeners()` after `_refreshCapturedImagePixelSize` (~`lib/screens/photo_capture/photo_capture_viewmodel.dart:1722`) will throw in debug if the screen left. `unawaited` POSTs keep mutating fields silently after pop.

**Do:**
- `lib/viewmodels/base_viewmodel.dart` with `bool _disposed`, `safeNotify()`, `Set<CancelToken>` + `addCancelToken()`, `dispose()` cancels all and sets `_disposed`.
- Refactor `ResultViewModel`, `CaptureViewModel`, `PhotoGenerateViewModel` to extend it.
- Pass cancel tokens into Dio calls (Retrofit accepts `@CancelRequest`).

**Done when:** A test pops a screen during an in-flight request and asserts no `notifyListeners after dispose` log.

---

### P0.4 — `PopScope` on payment/generation screens
**Problem:** Only `ThemeSelectionScreen` uses `PopScope` (`lib/screens/theme_selection/theme_selection_view.dart:336-381`). `PhotoGenerateProgressScreen.maybePop` (`lib/screens/photo_generate/photo_generate_progress_view.dart:126-129`) lets users pop while generation is in-flight. Result/Generate screens don't intercept back at all.

**Do:**
- Wrap `PhotoGenerateProgressScreen`, `PhotoGenerateScreen`, `ResultScreen` in `PopScope(canPop: false)`.
- Add explicit "Cancel & restart" affordance that calls `endPhotoboothCustomerSessionLogged('cancel: <screen>')` + navigates to slideshow.
- For staff flows, allow back via the existing staff PIN path only.

**Done when:** Manual test on a build — pressing system back during generation/payment is absorbed; the only exit is the explicit cancel button.

---

### P0.5 — Drop `ViewModel`-as-route-argument
**Problem:** `PhotoGenerateScreen` receives a fully-initialized `PhotoGenerateViewModel` as a route argument from progress (`lib/screens/photo_generate/photo_generate_view.dart:69-72`). If progress disposes early, destination renders against a zombie. `QrShareArgs.resultViewModel` is the same antipattern (`lib/utils/route_args.dart:141`).

**Do:**
- `PhotoGenerateScreen` constructs its own VM via `ChangeNotifierProvider(create: ...)`. Pass an immutable seed payload (or a `Future`/stream) through args.
- Same for `QrShare` — replace the `Object? resultViewModel` arg with the data the screen actually needs.

**Done when:** No `ChangeNotifier` instance passed via `Navigator.pushNamed` arguments anywhere in `lib/`.

---

## P1 — Architectural debt (high leverage)

### P1.1 (remainder) — `FrameSelectArgs` and `CaptureResult` types
Frame Select uses inline `Map` literals (e.g. `lib/screens/theme_selection/theme_selection_view.dart:216,258`). Capture returns implicit `PhotoModel?` with no contract.

**Do:** Add `FrameSelectArgs` and `CaptureResult` to `lib/utils/route_args.dart`; remove all `Map` fallbacks in screens; cover with negative-path tests in the same style as the existing arg tests.

**Done when:** `grep "arguments as Map" lib/screens/` returns zero hits.

---

### P1.3 — `DioFactory` + typed `ApiException` hierarchy
**Problem:** `api_client.dart`, `printer_api_client.dart`, plus on-the-fly Dio instances inside `ApiService` (`lib/services/api_service.dart:162-221`) and `PrintService` (`lib/services/print_service.dart:173-197`) each install their own interceptor stack. Logging interceptor registered twice on print flows. Printer requests lack `X-Client-*` headers. Every endpoint repeats 20–30 lines of `DioException` → `ApiException` mapping.

**Do:**
- `lib/services/network/dio_factory.dart` — returns a configured `Dio` (interceptors, headers, timeouts) given a `baseUrl`.
- One error-mapping interceptor that converts `DioException` → `RetryableApiException`, `AuthApiException`, `ValidationApiException`, `NetworkApiException`.
- Delete per-method `try/catch` blocks in `api_service.dart`; let the interceptor map.
- Both API clients (main + printer) use the factory.

**Done when:** `on DioException catch` blocks in `lib/services/api_service.dart` drop to ~zero.

---

### P1.4 — Split `api_service.dart` (1947 LOC) by domain
After P1.3 lands, extract `SessionApi`, `PaymentApi`, `GenerationApi`, `ThemeApi`, `KioskApi`. Move JSON streaming utilities (`_jsonStringCloseQuoteIndex`, `_stripEchoedUserImageUrlField`) to `lib/utils/api_payload_optimizer.dart`. Move retry/timeout policy to a Dio interceptor.

**Do not** apply the `part` + mixin pattern — split into actual classes.

**Done when:** No file in `lib/services/` exceeds ~500 LOC.

---

### P1.5 — Extract `CameraOperationQueue` from `CaptureViewModel`
`lib/screens/photo_capture/photo_capture_viewmodel.dart` (1925 LOC) bundles camera-hardware queue (`_cameraOp` lock, `:72,75-83`) + upload + preprocessing + recovery. Move the lock + camera controller lifecycle + rotation + resolution preset into `lib/services/camera/camera_operation_queue.dart`. Add unit tests on the queue (pure Dart, easy).

**Done when:** `CaptureViewModel` no longer holds the `_cameraOp` lock or the raw `CameraController`.

---

### P1.6 — Unify DI strategy
Pick one approach. Recommendation: keep Provider, register every long-lived service (SessionManager, ApiService, AppSettingsManager, KioskManager, PaymentPushCoordinator) as a singleton in the root `MultiProvider`. ViewModels receive them via constructor inside `ChangeNotifierProvider(create: (ctx) => ...)`. Delete singleton factories.

**Done when:** Grep for `static .* _instance` in `lib/services/` returns only `PaymentPushCoordinator` (which has a real reason to be a singleton, but should still be Provider-backed).

---

### P1.7 — Consistent VM ownership
Every screen uses `ChangeNotifierProvider(create: (ctx) => ...)` at the screen root. No `ChangeNotifierProvider.value` for VMs created by the screen itself. No VMs as private fields on a `State`.

**Done when:** Every `*ViewModel` instance is created inside a `ChangeNotifierProvider(create:)` callback.

---

### P1.8 — `Result<T, AppError>` for service → VM error flow
Each VM does its own `catch (e) { _errorMessage = ...; }` (`photo_capture_viewmodel.dart:1824`); some swallow with bare `catch (_) {}` (`:1277,1342`, `result_viewmodel.dart:647`). UI string-matches messages.

**Do:** Introduce `Result<T, AppError>` (or `dartz`/`fpdart`). Services return `Result`. VMs map to UI state. A single `ErrorPresenter` produces user-facing copy + Bugsnag breadcrumbs.

**Done when:** Bare `catch (_) {}` in `lib/screens/` and `lib/services/` is reviewed and either justified inline or replaced.

---

## P2 — Cleanup / hygiene

### P2.1 — Follow-ups on the photo_generate split
- Replace the unsafe `_page => this as _PhotoGenerateScreenState` cast in `lib/screens/photo_generate/photo_generate_view_widgets.dart:4`.
- The mixin contains `setState(() { _page._zoomedSlotId = ... })` (`photo_generate_view_widgets.dart:1002-1005`). Move state mutations back to the state class; the mixin should be widget builders only.
- When this code is touched again, prefer extracting `StatelessWidget` subclasses (`_GeneratedImageGrid`, `_GenerateActionsBar`) over expanding the mixin.

### P2.2 — Don't apply `part`+mixin to viewmodels or `api_service.dart`
For viewmodels and the API service the problem is **cohesion**, not file size. See P1.4 / P1.5.

### P2.3 — `PreferencesService` wrapper
SharedPreferences accessed in ~11 files (rotation key in both `photo_capture_viewmodel.dart` and `kiosk_manager.dart`). Wrap in `lib/services/preferences_service.dart` so keys live in one place and migrations are possible.

### P2.4 (remainder) — Bugsnag throttling
Gate `recordError` on `severity != info` in `lib/services/api_logging_interceptor.dart:98-118`. Polling endpoints (payment status) generate ~720 events/hour at 5s intervals. Demote retries to breadcrumbs.

### P2.5 — Dead code
- `_handleWebNetworkError` invoked on every error in `api_service.dart` even on mobile.
- `@deprecated updateSessionWithPhoto` at `photo_capture_viewmodel.dart:1845` — delete or document.

### P2.6 — Secure storage
`flutter_secure_storage` is in `pubspec.yaml:57` but unused. Either adopt it for the kiosk auth token (currently in SharedPreferences — security gap) or drop the dep.

### P2.7 — Stable client identification
`ClientIdentification` regenerates on reinstall — no hardware ID. For fleet correlation in Bugsnag, add `Build.SERIAL`/`identifierForVendor`.

### P2.8 — Image cache directory
`image_cache_service.dart:25` uses `getTemporaryDirectory()` which Android can reclaim. Switch to `getApplicationCacheDirectory()` so themes survive memory pressure on long-running kiosks.

### P2.9 — Print service temp file leak
Cleanup runs only on success path (`print_service.dart:251-254`). Wrap in `try/finally`.

### P2.10 — Stricter analyzer rules
Add to `analysis_options.yaml`: `unawaited_futures`, `await_only_futures`, `discarded_futures`, `cancel_subscriptions`, `close_sinks`. Will surface several P0/P1 findings for free.

### P2.11 — `Selector` instead of top-level `Consumer`
`photo_capture_view.dart:179` rebuilds the entire tree on every camera frame state change. Split into `Selector`s for the specific fields each subtree needs.

### P2.12 — Tests on the risky bits
Currently 6 test files vs 127 lib files. Highest-leverage missing tests:
- `PaymentPushCoordinator` — FCM cold-start, queue ordering, cross-session contamination after `resetForNextCustomer()`.
- `CameraOperationQueue` (after P1.5).
- `BaseViewModel` (after P0.3) — notify-after-dispose, cancel-on-dispose.

---

## Recommended next sequence

1. **P0.4 — `PopScope` + Cancel & restart.** Smallest, immediate UX safety; reuses the chokepoint that already exists.
2. **P0.1 (remainder) — `KioskIdleWatcher` + resume abandonment.** Closes the time-driven leak. Single-file resume check first; idle watcher second since it's the bigger lift.
3. **P0.3 — `BaseViewModel`.** Unblocks every later VM cleanup. The bugs it prevents (notify-after-dispose, mid-flight requests writing to dead state) cause flaky Bugsnag noise rather than visible breakage, so it's easy to defer indefinitely if not done now.
4. **P0.5 — Drop `ChangeNotifier`-as-arg.** Once `BaseViewModel` exists this is clean.
5. **P1.1 (remainder) — `FrameSelectArgs` + `CaptureResult`.** Finishes the typed-args sweep.
6. **P1.3 → P1.4 — `DioFactory` then `ApiService` split.** Factory unblocks the split.
7. **P1.5 — `CameraOperationQueue`.** Self-contained; good template for other VM extractions.
8. **P1.6 → P1.7 → P1.8 — DI + lifecycle + error-flow.** Together.
9. **P2.x — Cleanup, in any order.** P2.10 (analyzer rules) is the highest free leverage.

## Out of scope for this brief

- A full `repositories/` layer between viewmodels and services. Worth doing eventually; product-architecture change, not a refactor.
- Localization / i18n.
- UI polish, animations, theming.
- Performance profiling beyond the rebuild-storm note in P2.11.
