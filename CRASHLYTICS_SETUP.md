# Firebase Crashlytics Setup & Usage Guide

## ✅ What Was Added

Firebase Crashlytics has been integrated into the Photo Booth app to automatically track crashes, errors, and provide detailed diagnostics.

## 📦 Dependencies Added

### pubspec.yaml
```yaml
# Firebase
firebase_core: ^3.8.1
firebase_crashlytics: ^4.2.0
```

## 🔧 Configuration Files

### Android

**android/build.gradle.kts** - Added Firebase plugins:
```kotlin
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
        classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.2")
    }
}
```

**android/app/build.gradle.kts** - Applied plugins:
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")        // ← NEW
    id("com.google.firebase.crashlytics")       // ← NEW
}
```

**android/app/google-services.json** - Already exists ✅

### iOS

**ios/GoogleService-Info.plist** - Already exists ✅

**ios/Podfile** - No changes needed, Flutter will auto-install Firebase pods

## 📱 Installation Steps

### 1. Install Dependencies

```bash
# Get Flutter packages
flutter pub get

# For iOS only - install CocoaPods
cd ios
pod install
cd ..
```

### 2. Clean Build (Recommended)

```bash
# Clean previous builds
flutter clean

# Rebuild
flutter run
```

### 3. Verify Setup

Run the app and check logs for:
```
✅ Firebase initialized
✅ Crashlytics collection enabled
```

## 🎯 How It Works

### Automatic Crash Detection

All uncaught errors are automatically sent to Firebase Crashlytics:

1. **Flutter Framework Errors** - Caught by `FlutterError.onError`
2. **Async Errors** - Caught by `PlatformDispatcher.instance.onError`
3. **Native Crashes** - Automatically captured by Firebase SDK

### AppLogger Integration

The existing `AppLogger` class now sends errors and warnings to Crashlytics:

```dart
// This will be logged locally AND sent to Crashlytics
AppLogger.error('Camera initialization failed', 
  error: exception, 
  stackTrace: stackTrace
);

// Warnings are also tracked
AppLogger.warning('Low memory detected');

// Debug and info logs are added as breadcrumbs
AppLogger.debug('User opened photo capture screen');
```

## 📝 Usage Examples

### Basic Usage (Already Integrated)

Your existing code already works with Crashlytics:

```dart
// In your ViewModels or Services
try {
  await _cameraService.initializeCamera(camera);
} catch (e, stackTrace) {
  // This automatically goes to Crashlytics
  AppLogger.error('Failed to initialize camera', 
    error: e, 
    stackTrace: stackTrace
  );
}
```

### Advanced Usage with Context

Use `CrashlyticsHelper` for more detailed tracking:

```dart
import 'package:photobooth/utils/crashlytics_helper.dart';

// Set user ID (do this on app start or login)
await CrashlyticsHelper.setUserId(userId);

// Set camera context before camera operations
await CrashlyticsHelper.setCameraContext(
  cameraId: camera.name,
  cameraDirection: camera.lensDirection.toString(),
  isExternal: camera.lensDirection == CameraLensDirection.external,
);

// Set photo capture context
await CrashlyticsHelper.setPhotoCaptureContext(
  photoId: photo.id,
  sessionId: sessionId,
  themeId: selectedTheme.id,
);

// Log important events as breadcrumbs
CrashlyticsHelper.log('User switched to external camera');

// Record non-fatal errors manually
try {
  await riskyOperation();
} catch (e, stackTrace) {
  await CrashlyticsHelper.recordError(
    e, 
    stackTrace,
    reason: 'Failed during photo transformation',
    fatal: false,
  );
}
```

### Example: Camera ViewModel Integration

```dart
class CaptureViewModel extends ChangeNotifier {
  Future<void> initializeCamera(CameraDescription camera) async {
    // Set context for better crash reports
    await CrashlyticsHelper.setCameraContext(
      cameraId: camera.name,
      cameraDirection: camera.lensDirection.toString(),
      isExternal: camera.lensDirection == CameraLensDirection.external,
    );
    
    CrashlyticsHelper.log('Starting camera initialization: ${camera.name}');
    
    try {
      await _cameraService.initializeCamera(camera);
      CrashlyticsHelper.log('Camera initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Camera initialization failed', 
        error: e, 
        stackTrace: stackTrace
      );
      rethrow;
    }
  }
}
```

## 🧪 Testing Crashlytics

### Method 1: Test Crash Button (Debug Only)

Add a test button in your app:

```dart
// In a debug screen or settings
if (kDebugMode) {
  CupertinoButton(
    onPressed: () => CrashlyticsHelper.forceCrash(),
    child: Text('Test Crash'),
  );
}
```

### Method 2: Trigger from Code

```dart
// Add this temporarily to test
if (kDebugMode) {
  throw Exception('Test Crashlytics exception');
}
```

### Method 3: Simulate Real Error

```dart
// Add this to camera initialization to test
AppLogger.error('Test camera error', 
  error: Exception('Simulated camera failure'),
  stackTrace: StackTrace.current,
);
```

### Verify in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Crashlytics** in the left menu
4. Wait 1-2 minutes for crashes to appear
5. You should see the test crash with full stack trace

## 📊 Viewing Crash Reports

### Firebase Console

1. **Dashboard**: Overview of crash-free users, crashes, and trends
2. **Issues**: List of unique crash types with occurrence count
3. **Details**: Click any issue to see:
   - Stack trace
   - Device info (model, OS version)
   - Custom keys (camera info, session info)
   - Breadcrumbs (log messages leading up to crash)
   - Number of affected users

### Key Metrics to Monitor

- **Crash-free users %**: Should be > 99%
- **Crash velocity**: Crashes per user session
- **Top crashes**: Most common issues to fix first
- **Device distribution**: Which devices/OS versions crash most

## 🔍 Debugging with Crashlytics Data

When a crash occurs, you'll have access to:

1. **Stack Trace**: Exact line where crash occurred
2. **Custom Keys**: 
   - Camera ID, direction, external status
   - Photo ID, session ID, theme ID
   - User ID (if set)
3. **Breadcrumbs**: Log messages showing what user did before crash
4. **Device Info**: Model, OS version, memory, storage
5. **App Info**: Version, build number

### Example Crash Report

```
Exception: Camera initialization failed
Stack Trace:
  #0 CameraService.initializeCamera (camera_service.dart:750)
  #1 CaptureViewModel.initializeCamera (photo_capture_viewmodel.dart:235)
  
Custom Keys:
  camera_id: "Camera 2"
  camera_direction: "CameraLensDirection.external"
  is_external_camera: true
  session_id: "abc123"
  
Breadcrumbs:
  [10:30:15] User opened photo capture screen
  [10:30:16] Available cameras loaded: 3
  [10:30:18] User selected external camera
  [10:30:19] Starting camera initialization: Camera 2
  [10:30:20] ❌ Camera initialization failed
```

## 🛡️ Privacy & User Consent

### Disable Crashlytics for Privacy

If your app needs user consent for crash reporting:

```dart
// On app first launch, ask user
if (userOptedOutOfCrashReporting) {
  await CrashlyticsHelper.setCrashlyticsCollectionEnabled(false);
  await CrashlyticsHelper.deleteUnsentReports();
}
```

### Check Status

```dart
bool isEnabled = await CrashlyticsHelper.isCrashlyticsCollectionEnabled();
```

## 📱 Platform-Specific Notes

### Android

- **Minimum SDK**: 20 (already configured)
- **ProGuard**: Crashlytics works with ProGuard automatically
- **Mapping Files**: Automatically uploaded during build
- **Instant Run**: Disable for testing crashes (not an issue in release)

### iOS

- **Minimum iOS**: 11.0 (your app requires 17.0, so no issue)
- **dSYM Upload**: Automatically handled by Firebase SDK
- **Bitcode**: Not needed (deprecated by Apple)

### Android TV

Crashlytics works on Android TV without any special configuration. The camera loader issue will now be tracked if it occurs again.

## 🔧 Troubleshooting

### "Crashlytics not initialized" Error

**Solution**: Make sure Firebase.initializeApp() completes before using Crashlytics:

```dart
await Firebase.initializeApp();
// Now safe to use Crashlytics
```

### Crashes Not Appearing in Console

**Possible Causes**:
1. **Debug Mode**: Crashes might be delayed. Close and reopen app.
2. **Network**: Crashes are queued and sent when network is available
3. **Firebase Project**: Verify correct google-services.json/GoogleService-Info.plist
4. **Time**: New projects can take up to 24 hours to activate

**Solutions**:
```bash
# Verify Firebase setup
flutter pub run firebase_crashlytics:configure

# Force send unsent reports
CrashlyticsHelper.sendUnsentReports();
```

### iOS Build Errors

**Error**: "No such module 'FirebaseCrashlytics'"

**Solution**:
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter clean
flutter run
```

### Android Build Errors

**Error**: "Could not find com.google.gms:google-services"

**Solution**:
1. Check internet connection
2. Clean build:
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter run
```

## 📈 Best Practices

### 1. Use Custom Keys Strategically

```dart
// Good - helps diagnose issue
await CrashlyticsHelper.setCustomKey('camera_type', 'external_usb');
await CrashlyticsHelper.setCustomKey('photo_resolution', '1920x1080');

// Bad - too verbose, not useful
await CrashlyticsHelper.setCustomKey('timestamp', DateTime.now().toString());
```

### 2. Log Important Events as Breadcrumbs

```dart
// Good - shows user flow
CrashlyticsHelper.log('User started photo capture');
CrashlyticsHelper.log('User selected theme: Modern');
CrashlyticsHelper.log('Photo uploaded successfully');

// Bad - too much noise
CrashlyticsHelper.log('Button pressed'); // Not specific enough
```

### 3. Record Non-Fatal Errors

```dart
// Good - track errors that don't crash but cause issues
try {
  await uploadPhoto();
} catch (e, stackTrace) {
  await CrashlyticsHelper.recordError(e, stackTrace, 
    reason: 'Photo upload failed but continuing',
    fatal: false,
  );
  // Show error to user, continue operation
}
```

### 4. Clean Up Context

```dart
// When user logs out or starts new session
await CrashlyticsHelper.clearContext();
await CrashlyticsHelper.setUserId(newUserId);
```

## 🚀 Production Checklist

- [ ] Firebase project created and configured
- [ ] google-services.json added to android/app/
- [ ] GoogleService-Info.plist added to ios/
- [ ] Dependencies installed (`flutter pub get`)
- [ ] iOS pods installed (`cd ios && pod install`)
- [ ] Test crash verified in Firebase Console
- [ ] AppLogger integration tested
- [ ] Privacy policy updated (if required)
- [ ] User consent flow added (if required)
- [ ] ProGuard rules verified (Android release)
- [ ] dSYM upload verified (iOS release)

## 📚 Additional Resources

- [Firebase Crashlytics Documentation](https://firebase.google.com/docs/crashlytics)
- [FlutterFire Crashlytics](https://firebase.flutter.dev/docs/crashlytics/overview)
- [Crashlytics Best Practices](https://firebase.google.com/docs/crashlytics/best-practices)
- [Privacy & Compliance](https://firebase.google.com/support/privacy)

## 🎯 Summary

Firebase Crashlytics is now fully integrated and will:
- ✅ Automatically capture all crashes and errors
- ✅ Send AppLogger errors and warnings to Firebase
- ✅ Track custom context (camera info, session info)
- ✅ Provide breadcrumbs for debugging
- ✅ Help you fix issues faster with detailed reports

The camera loader issue on Android TV will now be tracked automatically if it occurs again, with full context about which camera was being used and what operations were in progress.
