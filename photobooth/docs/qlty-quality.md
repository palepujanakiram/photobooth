# Scoped test coverage (Qlty)

Unit-testable logic is gated at **100% line coverage** on a curated scope (not every line in `lib/`, including UI shells and platform integration).

## Commands

From `photobooth/`:

```bash
flutter test --coverage
dart run tool/verify_coverage_scope.dart
```

`verify_coverage_scope.dart` mirrors `[coverage].ignores` in `.qlty/qlty.toml` (views, generated code, FCM/print, Dio factories, legacy media upload, etc.).

## In-scope highlights

- `lib/services/api_session_patch_json.dart`
- `lib/services/api_sse_dispatch.dart`
- `lib/services/api_image_url_utils.dart`
- `lib/services/kiosk_manager.dart`

`api_service.dart` is covered by dedicated mock-Dio tests but excluded from the gate because remaining lines are web-only error paths.
