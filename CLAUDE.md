# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a monorepo. The Flutter app lives entirely in `photobooth/`. Run **all** Flutter and Dart commands from that directory.

```
photobooth/          ← Flutter package root (pubspec.yaml, lib/, android/, ios/)
  lib/
    screens/         ← one folder per screen: *_view.dart + *_viewmodel.dart
    services/        ← API, session, theme, print, share, file, FCM, error reporting
    models/          ← shared data models
    utils/           ← constants, logger, exceptions, app_config, route names
    views/widgets/   ← reusable UI (AppScaffold, ThemeCard, CachedNetworkImage, …)
  packages/
    camera_native_details/      ← local plugin: Android Camera2 detail queries; stubs for iOS/Web
    camera_android_camerax/     ← vendored fork of the official plugin (do not edit; excluded from analyzer)
  tool/                         ← Dart CLI scripts (sync_build_version, verify_coverage_scope, …)
  scripts/                      ← shell helpers (flutter_with_version.sh)
.cursor/rules/       ← Cursor MDC rules (project-overview, dart-flutter, sonar-quality-gates)
```

## Commands

All commands run from `photobooth/` unless noted.

```bash
# Dependencies
flutter pub get

# Analyze
flutter analyze lib/

# Tests
flutter test                          # all tests
flutter test test/path/to/foo_test.dart   # single test file
flutter test --coverage               # with coverage report

# Coverage gate (CI requirement)
dart run tool/verify_coverage_scope.dart

# Run (debug)
flutter run

# Build APK — must use the version-sync wrapper, not plain flutter build
./scripts/flutter_with_version.sh build apk
./scripts/flutter_with_version.sh build apk --release

# Build web
./scripts/flutter_with_version.sh build web

# Sync version stamp manually (updates pubspec version from date/time)
dart run tool/sync_build_version.dart

# Regenerate Retrofit / json_serializable code
dart run build_runner build --delete-conflicting-outputs
```

> **Do not use `flutter build apk` directly** — it skips the `dart run tool/sync_build_version.dart` step that keeps `pubspec.yaml` version and the Android `versionCode` in sync.

## Architecture: MVVM with Provider

The app follows a strict MVVM pattern. Screens own a ViewModel; the ViewModel owns all business logic and talks to services.

**ViewModels** (`*_viewmodel.dart`)
- Extend `ChangeNotifier`. Private state exposed via public getters. Call `notifyListeners()` after mutations.
- Receive services via constructor with production defaults (e.g. `ThemeManager? themeManager` defaulting to `ThemeManager()`). This makes them testable without mocks at the call site.
- Override `dispose()` to cancel timers, remove listeners, and release resources.

**Views** (`*_view.dart`)
- `context.read<MyViewModel>()` for one-shot calls; `context.watch<MyViewModel>()` to rebuild on state changes.
- Complex screens split their build output across `*_view_scaffold.dart`, `*_view_aspect.dart`, `*_view_widgets.dart`, `*_view_handlers.dart` to stay under the Sonar cognitive-complexity limit (≤15).

**Services** (`lib/services/`)
- `ApiService` — all backend HTTP calls via Dio + Retrofit (`ApiClient`). Constructor accepts optional `Dio? dio` for testing. Helpers extracted to `api_service_helpers.dart`, `api_dio_errors.dart`, `api_http_response.dart`, etc.
- `SessionManager` — holds the active kiosk session state.
- `ThemeManager` — fetches and caches AI transformation themes.
- `KioskManager` — kiosk identity and authorization.
- Platform-conditional implementations use the stub/io/web triple pattern (e.g. `file_helper.dart` re-exports `file_helper_io.dart` or `file_helper_web.dart`).

## User flow / screen sequence

```
Slideshow → Splash → Terms & Conditions → Theme Selection → [Frame Select] →
Photo Capture → Photo Generate (progress) → [Photo Review] → Result → QR Share → Thank You
```

Staff screens (`/staff-login`, `/staff-payments`) are a side path for event operators.

All route names are constants in `lib/utils/constants.dart`; the route table is in `lib/app_routes.dart`.

## Key conventions

**Configuration**: Change API base URL and bearer token in `lib/utils/app_config.dart` only (`--dart-define=BASE_URL=…` overrides at build time). No hardcoded API URLs elsewhere.

**Logging**: Use `AppLogger` from `utils/logger.dart`. Never use `print`.

**Errors**: Throw `ApiException` (from `utils/exceptions.dart`) for API failures; report via `ErrorReportingManager` (wraps Bugsnag; no-ops on web).

**Generated files**: `*.g.dart` files are Retrofit/json_serializable output — never edit them; regenerate with `dart run build_runner build`.

**Camera**: The app supports both the standard `camera` plugin and external/USB cameras via `uvccamera` (UVC protocol). External camera logic is in `lib/screens/photo_capture/photo_capture_uvc_screen.dart`. Camera selection helpers pick between them at runtime.

**Web**: Web is a secondary platform. File I/O, camera, and print paths use conditional imports (`dart.library.html` / `dart.library.io`) or stub files. On web, Dio requires `configureDioForWeb()` to avoid `SocketException`.

## Quality gates (required before merging)

```bash
flutter analyze lib/     # zero errors
flutter test --coverage
dart run tool/verify_coverage_scope.dart
```

- **No new** Sonar Maintainability / Reliability / Security / Duplication issues.
- **Coverage > 90%** on Sonar new code; **100%** on the in-scope unit-testable layer (services, utils, models, most ViewModels).
- New logic in `lib/services/`, `lib/utils/`, `lib/models/`, or ViewModels requires matching tests under `test/`.
- Pure UI files (`*_view.dart`, `*_view_widgets.dart`) are excluded from the coverage denominator.
- Sonar rules to watch: **S107** (≤7 params → use `*Input` classes), **S3776** (cognitive complexity ≤15 → extract helpers), **S1192** (repeated strings → `lib/utils/app_strings.dart`).
- SonarCloud project: `palepujanakiram_photobooth`.
