# Error Reporting Migration Guide

Migration from `CrashlyticsHelper` to `ErrorReportingManager`

## 🎯 Summary

The codebase has been refactored to use a new `ErrorReportingManager` system that provides:
- ✅ **Abstraction layer** over error reporting services
- ✅ **Easy to add new services** (Bugsnag, Sentry, etc.)
- ✅ **Single point of control** for enabling/disabling reporting
- ✅ **Same functionality** as before, just better organized

## 📊 What Changed?

### Before (Old System)
```dart
import '../../utils/crashlytics_helper.dart';

// Direct Crashlytics calls
CrashlyticsHelper.log('Photo captured');
await CrashlyticsHelper.recordError(e, stackTrace);
await CrashlyticsHelper.setCustomKey('camera_id', id);
```

### After (New System)
```dart
import '../../services/error_reporting/error_reporting_manager.dart';

// Abstracted through manager
ErrorReportingManager.log('Photo captured');
await ErrorReportingManager.recordError(e, stackTrace);
await ErrorReportingManager.setCustomKey('camera_id', id);
```

## 🔄 Migration Mapping

| Old (CrashlyticsHelper) | New (ErrorReportingManager) | Notes |
|--------------------------|----------------------------|-------|
| `CrashlyticsHelper.log(msg)` | `ErrorReportingManager.log(msg)` | Identical API |
| `CrashlyticsHelper.recordError(e, st, reason: r, information: i)` | `ErrorReportingManager.recordError(e, st, reason: r, extraInfo: map)` | `information` → `extraInfo` (now a Map) |
| `CrashlyticsHelper.setCustomKey(k, v)` | `ErrorReportingManager.setCustomKey(k, v)` | Identical API |
| `CrashlyticsHelper.setCustomKeys(map)` | `ErrorReportingManager.setCustomKeys(map)` | Identical API |
| `CrashlyticsHelper.setUserId(id)` | `ErrorReportingManager.setUserId(id)` | Identical API |
| `CrashlyticsHelper.clearContext()` | `ErrorReportingManager.clearContext()` | Identical API |
| `CrashlyticsHelper.setCameraContext(...)` | `ErrorReportingManager.setCameraContext(...)` | Identical API |
| `CrashlyticsHelper.setPhotoCaptureContext(...)` | `ErrorReportingManager.setPhotoCaptureContext(...)` | Identical API |

## 🔑 Key Difference: `information` → `extraInfo`

The biggest API change is in `recordError()`:

### Before
```dart
await CrashlyticsHelper.recordError(
  exception,
  stackTrace,
  reason: 'Photo capture failed',
  information: [
    'Camera: $cameraId',
    'Custom Controller: $useCustom',
    'Preview Running: $isRunning',
  ],
);
```

### After
```dart
await ErrorReportingManager.recordError(
  exception,
  stackTrace,
  reason: 'Photo capture failed',
  extraInfo: {
    'camera': cameraId,
    'custom_controller': useCustom,
    'preview_running': isRunning,
  },
);
```

**Why?** Using a Map is more flexible and works better across different error reporting services.

## 📦 New Architecture

```
Old System:
App Code → CrashlyticsHelper → Firebase Crashlytics

New System:
App Code → ErrorReportingManager → ErrorReportingService (Interface)
                                    ├── CrashlyticsErrorReporter
                                    ├── BugsnagErrorReporter (future)
                                    └── SentryErrorReporter (future)
```

## 🚀 Initialization Changes

### Before (main.dart)
```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  await Firebase.initializeApp();
  
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}
```

### After (main.dart)
```dart
import 'services/error_reporting/error_reporting_manager.dart';

void main() async {
  await Firebase.initializeApp();
  
  // Initialize error reporting
  await ErrorReportingManager.initialize(enableCrashlytics: true);
  
  FlutterError.onError = (errorDetails) {
    ErrorReportingManager.recordError(
      errorDetails.exception,
      errorDetails.stack,
      reason: 'Flutter Fatal Error',
      fatal: true,
    );
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReportingManager.recordError(
      error,
      stack,
      reason: 'Uncaught Async Error',
      fatal: true,
    );
    return true;
  };
}
```

## 📝 Files Updated

### Created Files (New)
1. `lib/services/error_reporting/error_reporting_service.dart` - Abstract interface
2. `lib/services/error_reporting/error_reporting_manager.dart` - Main facade
3. `lib/services/error_reporting/crashlytics_error_reporter.dart` - Crashlytics implementation
4. `lib/services/error_reporting/README.md` - Documentation

### Modified Files
1. `lib/main.dart` - Updated initialization
2. `lib/screens/photo_capture/photo_capture_viewmodel.dart` - Replaced CrashlyticsHelper calls
3. `lib/services/camera_service.dart` - Replaced CrashlyticsHelper calls
4. `lib/services/custom_camera_controller.dart` - Replaced CrashlyticsHelper calls

### Unchanged Files
- `lib/utils/crashlytics_helper.dart` - Still exists but deprecated (can be removed if not used elsewhere)

## ✅ Benefits of New System

### 1. **Easy to Add New Services**
Want to add Bugsnag alongside Crashlytics?

```dart
await ErrorReportingManager.initialize(
  enableCrashlytics: true,
  enableBugsnag: true,  // Just add this!
);
```

All errors now go to both services automatically!

### 2. **Easy to Toggle On/Off**
```dart
// Disable all error reporting (e.g., for user privacy)
await ErrorReportingManager.setEnabled(false);

// Re-enable
await ErrorReportingManager.setEnabled(true);
```

### 3. **Better Testing**
```dart
// In tests, disable actual reporting
setUp(() async {
  await ErrorReportingManager.setEnabled(false);
});
```

### 4. **Single Point of Change**
Need to switch from Crashlytics to Sentry? Just update the initialization in `main.dart`:

```dart
await ErrorReportingManager.initialize(
  enableCrashlytics: false,  // Turn off Crashlytics
  enableSentry: true,        // Turn on Sentry
);
```

No need to update any other code!

## 🧪 Testing the Migration

### 1. Build and Run
```bash
flutter clean
flutter pub get
flutter run
```

### 2. Verify Initialization
Check console output for:
```
✅ Error reporting initialized successfully
   Active services: 1
```

### 3. Test Error Logging
Trigger a photo capture error and check Firebase Crashlytics dashboard.

### 4. Check Custom Keys
Errors should still include custom keys like:
- `camera_id`
- `capture_isReady`
- `service_useCustomController`
- etc.

## 🔍 Backward Compatibility

The old `CrashlyticsHelper` still exists and can be used alongside the new system if needed. However:
- ✅ All new code should use `ErrorReportingManager`
- ⚠️ `CrashlyticsHelper` is considered deprecated
- 🔜 Plan to remove `CrashlyticsHelper` once fully migrated

## 📚 Next Steps

1. ✅ All camera-related code now uses `ErrorReportingManager`
2. 🔜 Consider adding Bugsnag or Sentry for redundancy
3. 🔜 Add user preference UI for enabling/disabling error reporting
4. 🔜 Remove deprecated `CrashlyticsHelper` (optional)

## 🆘 Troubleshooting

### "Error reporting not working"
```dart
// Check if initialized
print('Initialized: ${ErrorReportingManager.isInitialized}');

// Check if enabled
print('Enabled: ${ErrorReportingManager.isEnabled}');

// Check service count
print('Services: ${ErrorReportingManager.serviceCount}');
```

### "No errors appearing in Crashlytics"
- Ensure Firebase is configured correctly
- Wait 2-5 minutes for logs to appear
- Check that `enableCrashlytics: true` in initialization
- Verify internet connection on test device

### "Import errors"
Make sure to import the correct path:
```dart
import 'services/error_reporting/error_reporting_manager.dart';
// NOT: import 'utils/crashlytics_helper.dart';
```

## 📖 More Information

- See `lib/services/error_reporting/README.md` for complete documentation
- See code examples in updated files for usage patterns
- Check inline comments in `error_reporting_manager.dart` for API details

---

**Questions?** Review the comprehensive README in `lib/services/error_reporting/README.md`
