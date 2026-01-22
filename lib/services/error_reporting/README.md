# Error Reporting Manager

A flexible, extensible error reporting system that provides a unified interface for logging and error tracking across multiple services.

## 📋 Overview

The `ErrorReportingManager` is a centralized facade that manages error reporting services. It currently uses Firebase Crashlytics but can easily support multiple services simultaneously (Bugsnag, Sentry, etc.).

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│     Application Code                │
│  (ViewModels, Services, etc.)       │
└──────────────┬──────────────────────┘
               │
               │ Uses
               ▼
┌─────────────────────────────────────┐
│    ErrorReportingManager            │
│  (Unified Interface / Facade)       │
└──────────────┬──────────────────────┘
               │
               │ Manages
               ▼
┌─────────────────────────────────────┐
│   ErrorReportingService             │
│   (Abstract Interface)              │
└──────────────┬──────────────────────┘
               │
         ┌─────┴─────┐
         │           │
         ▼           ▼
┌──────────────┐ ┌──────────────┐
│ Crashlytics  │ │   Bugsnag    │
│   Reporter   │ │   Reporter   │
│  (Current)   │ │  (Future)    │
└──────────────┘ └──────────────┘
```

## 🚀 Quick Start

### 1. Initialize in `main.dart`

```dart
import 'services/error_reporting/error_reporting_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize ErrorReportingManager
  await ErrorReportingManager.initialize(
    enableCrashlytics: true,  // Enable Crashlytics
    // Add more services here in the future
  );
  
  // Set up global error handlers
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
  
  runApp(MyApp());
}
```

### 2. Use in Your Code

#### Basic Logging
```dart
// Log breadcrumbs (sequence of events)
ErrorReportingManager.log('User opened camera screen');
ErrorReportingManager.log('📸 Photo capture started');
```

#### Record Errors
```dart
try {
  await someDangerousOperation();
} catch (e, stackTrace) {
  await ErrorReportingManager.recordError(
    e,
    stackTrace,
    reason: 'Failed to perform operation',
    extraInfo: {
      'user_id': userId,
      'operation_type': 'photo_capture',
    },
  );
}
```

#### Set Context (Custom Keys)
```dart
// Set single key
await ErrorReportingManager.setCustomKey('user_type', 'premium');

// Set multiple keys
await ErrorReportingManager.setCustomKeys({
  'camera_id': 'external_camera_123',
  'is_external': true,
  'preview_running': true,
});

// Use convenience methods
await ErrorReportingManager.setCameraContext(
  cameraId: 'external_camera_123',
  cameraDirection: 'external',
  isExternal: true,
);

await ErrorReportingManager.setPhotoCaptureContext(
  photoId: 'photo_abc123',
  sessionId: 'session_xyz789',
  themeId: 'theme_001',
);
```

#### Set User ID
```dart
await ErrorReportingManager.setUserId('user_12345');
```

#### Clear Context
```dart
// Clear all custom keys (useful when logging out)
await ErrorReportingManager.clearContext();
```

## 🔧 Enable/Disable Error Reporting

### Check Status
```dart
if (ErrorReportingManager.isEnabled) {
  print('Error reporting is active');
}
```

### Toggle On/Off
```dart
// Disable error reporting (e.g., for user privacy preference)
await ErrorReportingManager.setEnabled(false);

// Re-enable
await ErrorReportingManager.setEnabled(true);
```

When disabled:
- All `log()` calls become no-ops
- All `recordError()` calls become no-ops
- No data is sent to any error reporting service

## 📊 Benefits

### 1. **Single Point of Control**
- Change error reporting service without touching app code
- Enable/disable all error reporting with one call
- Consistent logging across the entire app

### 2. **Flexibility**
- Easy to add new error reporting services
- Can use multiple services simultaneously
- Each service can be toggled independently

### 3. **Privacy & Compliance**
- Easy to respect user privacy preferences
- One place to control data collection
- Useful for GDPR/CCPA compliance

### 4. **Testing & Debugging**
- Disable reporting during development
- No spam in production dashboards from test builds
- Easy to mock for unit tests

## 🆕 Adding a New Service (e.g., Bugsnag)

### Step 1: Create the Reporter Class

Create `lib/services/error_reporting/bugsnag_error_reporter.dart`:

```dart
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'error_reporting_service.dart';

class BugsnagErrorReporter implements ErrorReportingService {
  bool _isEnabled = true;

  @override
  Future<void> initialize() async {
    await bugsnag.start(
      apiKey: 'YOUR_BUGSNAG_API_KEY',
    );
  }

  @override
  void log(String message) {
    if (!_isEnabled) return;
    bugsnag.leaveBreadcrumb(message);
  }

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? extraInfo,
    bool fatal = false,
  }) async {
    if (!_isEnabled) return;
    
    await bugsnag.notify(
      exception,
      stackTrace,
      callback: (event) {
        if (reason != null) {
          event.context = reason;
        }
        if (extraInfo != null) {
          event.metadata.addAll({'extra': extraInfo});
        }
      },
    );
  }

  @override
  Future<void> setUserId(String userId) async {
    if (!_isEnabled) return;
    bugsnag.setUser(userId: userId);
  }

  @override
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled) return;
    bugsnag.addMetadata('custom', {key: value});
  }

  @override
  Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    if (!_isEnabled) return;
    bugsnag.addMetadata('custom', keys);
  }

  @override
  Future<void> clearContext() async {
    if (!_isEnabled) return;
    bugsnag.clearMetadata('custom');
  }

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
  }
}
```

### Step 2: Register in ErrorReportingManager

Update `error_reporting_manager.dart`:

```dart
import 'bugsnag_error_reporter.dart';

static Future<void> initialize({
  bool enableCrashlytics = true,
  bool enableBugsnag = false,  // Add this parameter
}) async {
  if (_isInitialized) return;

  if (enableCrashlytics) {
    _services.add(CrashlyticsErrorReporter());
  }

  if (enableBugsnag) {  // Add this block
    _services.add(BugsnagErrorReporter());
  }

  for (final service in _services) {
    await service.initialize();
  }

  _isInitialized = true;
}
```

### Step 3: Enable in main.dart

```dart
await ErrorReportingManager.initialize(
  enableCrashlytics: true,
  enableBugsnag: true,  // Enable Bugsnag
);
```

That's it! Now errors will be sent to both Crashlytics and Bugsnag automatically.

## 📝 API Reference

### Static Methods

| Method | Description |
|--------|-------------|
| `initialize()` | Initialize all error reporting services |
| `log(String message)` | Log a breadcrumb/event |
| `recordError()` | Record a non-fatal error |
| `setUserId(String userId)` | Set user identifier |
| `setCustomKey(key, value)` | Set a single custom key |
| `setCustomKeys(Map)` | Set multiple custom keys |
| `clearContext()` | Clear all custom context |
| `setEnabled(bool)` | Enable/disable error reporting |
| `setCameraContext()` | Convenience: set camera-related keys |
| `setPhotoCaptureContext()` | Convenience: set photo-related keys |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isEnabled` | `bool` | Whether error reporting is enabled |
| `isInitialized` | `bool` | Whether manager has been initialized |
| `serviceCount` | `int` | Number of active error reporting services |

## 🧪 Testing

### Mock for Unit Tests

```dart
// In your test setup
class MockErrorReportingService implements ErrorReportingService {
  final logs = <String>[];
  final errors = <dynamic>[];
  
  @override
  void log(String message) {
    logs.add(message);
  }
  
  @override
  Future<void> recordError(...) async {
    errors.add(exception);
  }
  
  // Implement other methods...
}

// In tests
void main() {
  setUp(() async {
    // Disable actual error reporting in tests
    await ErrorReportingManager.setEnabled(false);
  });
  
  test('should log photo capture', () {
    ErrorReportingManager.log('Photo captured');
    // Verify behavior...
  });
}
```

## 🔒 Privacy Considerations

The ErrorReportingManager makes it easy to respect user privacy:

```dart
// Example: User privacy preference
class SettingsService {
  Future<void> setErrorReportingEnabled(bool enabled) async {
    await ErrorReportingManager.setEnabled(enabled);
    // Save preference...
  }
}

// In settings UI
Switch(
  value: errorReportingEnabled,
  onChanged: (value) async {
    await settingsService.setErrorReportingEnabled(value);
  },
);
```

## 📦 Current Implementation

### Active Services
- ✅ **Firebase Crashlytics** (via `CrashlyticsErrorReporter`)

### Supported Operations
- ✅ Breadcrumb logging
- ✅ Error recording with stack traces
- ✅ Custom key-value pairs
- ✅ User identification
- ✅ Enable/disable per service
- ✅ Global enable/disable

### Future Services (Easy to Add)
- 🔜 Bugsnag
- 🔜 Sentry
- 🔜 Custom logging server
- 🔜 Analytics integration

## 💡 Best Practices

### 1. **Log Progression, Not Spam**
```dart
// Good
ErrorReportingManager.log('User started photo capture');
ErrorReportingManager.log('Camera initialized');
ErrorReportingManager.log('Photo captured successfully');

// Bad (too noisy)
ErrorReportingManager.log('Loop iteration 1');
ErrorReportingManager.log('Loop iteration 2');
// ...
```

### 2. **Provide Context with Errors**
```dart
// Good
await ErrorReportingManager.recordError(
  exception,
  stackTrace,
  reason: 'Photo capture timeout',
  extraInfo: {
    'camera_id': cameraId,
    'timeout_duration': '8s',
    'device_model': deviceModel,
  },
);

// Less helpful
await ErrorReportingManager.recordError(exception, stackTrace);
```

### 3. **Set Context Early**
```dart
// Set context before operations
await ErrorReportingManager.setCameraContext(
  cameraId: selectedCamera.id,
  isExternal: true,
);

// Now all future errors will include this context
try {
  await capturePhoto();
} catch (e, stack) {
  // Error will include camera context automatically
  await ErrorReportingManager.recordError(e, stack);
}
```

### 4. **Clear Context When Appropriate**
```dart
// When user logs out
await ErrorReportingManager.clearContext();
await ErrorReportingManager.setUserId('');

// When starting new session
await ErrorReportingManager.clearContext();
await ErrorReportingManager.setPhotoCaptureContext(
  sessionId: newSessionId,
);
```

## 🐛 Troubleshooting

### Errors Not Appearing in Dashboard?
1. Check if error reporting is enabled:
   ```dart
   print('Enabled: ${ErrorReportingManager.isEnabled}');
   ```
2. Check if services are initialized:
   ```dart
   print('Initialized: ${ErrorReportingManager.isInitialized}');
   print('Services: ${ErrorReportingManager.serviceCount}');
   ```
3. Check Firebase configuration (if using Crashlytics)
4. Wait 2-5 minutes for logs to appear in dashboard

### Want to Verify Logging?
Add debug prints in development:

```dart
// In ErrorReportingManager
static void log(String message) {
  if (!_isEnabled) return;
  
  if (kDebugMode) {
    print('[ErrorReporting] $message');
  }
  
  for (final service in _services) {
    service.log(message);
  }
}
```

## 📚 Related Files

- `error_reporting_service.dart` - Abstract interface
- `error_reporting_manager.dart` - Main facade
- `crashlytics_error_reporter.dart` - Crashlytics implementation
- `../../main.dart` - Initialization code
- `../camera_service.dart` - Usage example
- `../../screens/photo_capture/photo_capture_viewmodel.dart` - Usage example

---

**Need help?** Check the inline documentation in each file or review usage examples in the codebase.
