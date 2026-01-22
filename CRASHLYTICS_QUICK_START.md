# Crashlytics Quick Start Guide

## 🚀 Installation (2 minutes)

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. iOS Setup

```bash
cd ios
pod install
cd ..
```

### 3. Clean Build

```bash
flutter clean
flutter run
```

## ✅ That's It!

Crashlytics is now integrated and will automatically:
- 📊 Track all crashes
- 🐛 Capture errors from `AppLogger.error()` and `AppLogger.warning()`
- 📝 Log breadcrumbs for debugging
- 📱 Track device and app info

## 🧪 Test It (1 minute)

### Option 1: Add Test Button

Add this to any screen temporarily:

```dart
import 'package:flutter/foundation.dart';
import 'package:photobooth/utils/crashlytics_helper.dart';

// In your widget build method
if (kDebugMode) {
  CupertinoButton(
    child: Text('Test Crash'),
    onPressed: () => CrashlyticsHelper.forceCrash(),
  );
}
```

### Option 2: Trigger Test Error

Add this to any method:

```dart
AppLogger.error('Test error for Crashlytics',
  error: Exception('This is a test'),
  stackTrace: StackTrace.current,
);
```

### View in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click **Crashlytics** in left menu
4. Wait 1-2 minutes
5. See your test crash! 🎉

## 📋 What Changed

### Files Modified:
- ✅ `pubspec.yaml` - Added Firebase dependencies
- ✅ `android/build.gradle.kts` - Added Firebase plugins
- ✅ `android/app/build.gradle.kts` - Applied plugins
- ✅ `lib/main.dart` - Initialize Firebase & Crashlytics
- ✅ `lib/utils/logger.dart` - Send errors to Crashlytics
- ✅ `lib/screens/photo_capture/photo_capture_viewmodel.dart` - Added context tracking

### Files Created:
- ✅ `lib/utils/crashlytics_helper.dart` - Helper utilities
- ✅ `CRASHLYTICS_SETUP.md` - Full documentation
- ✅ `CRASHLYTICS_QUICK_START.md` - This file

## 🎯 Already Working

Your existing code already sends errors to Crashlytics:

```dart
// This automatically goes to Crashlytics now
AppLogger.error('Camera failed', error: e, stackTrace: stackTrace);
AppLogger.warning('Low memory');
```

## 📊 Enhanced Camera Tracking

The camera code now tracks:
- Camera ID and type (external/built-in)
- Photo capture success/failure
- Session ID for tracking user flows
- Breadcrumbs showing user actions

## 📱 Android TV Loader Issue

If the Android TV loader issue happens again, you'll now see:
- Exact error message and stack trace
- Which camera was being used
- What operation was in progress
- Device and OS version
- Complete user flow leading to issue

## 🔧 Troubleshooting

### Crashes Not Showing?

1. **Wait 2 minutes** - Crashes are uploaded in batches
2. **Reopen app** - Crashes are sent on next app start
3. **Check network** - Requires internet connection
4. **Verify setup**:
   ```bash
   flutter pub run firebase_crashlytics:configure
   ```

### Build Errors?

**Android**:
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter run
```

**iOS**:
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter clean
flutter run
```

## 📚 Learn More

See `CRASHLYTICS_SETUP.md` for:
- Advanced usage examples
- Privacy & user consent
- Custom context tracking
- Best practices
- Platform-specific notes

## 🎉 Benefits

### Before Crashlytics:
- ❌ Crashes happened silently
- ❌ Users reported "app not working"
- ❌ No way to reproduce issues
- ❌ Had to guess what went wrong

### After Crashlytics:
- ✅ Every crash is tracked automatically
- ✅ Stack traces show exact line of code
- ✅ Device info helps reproduce issues
- ✅ Breadcrumbs show user actions
- ✅ Can fix issues before users report them

## 🔒 Privacy Note

Crashlytics collects:
- ✅ Crash stack traces (anonymous)
- ✅ Device info (model, OS version)
- ✅ App version
- ✅ Custom keys you set (camera ID, etc.)

Crashlytics does NOT collect:
- ❌ Personal information
- ❌ User photos
- ❌ User credentials
- ❌ Location data

You can disable Crashlytics for users who opt out:
```dart
await CrashlyticsHelper.setCrashlyticsCollectionEnabled(false);
```

## 📞 Support

If you have questions:
1. Check `CRASHLYTICS_SETUP.md` for detailed docs
2. See [Firebase Crashlytics Docs](https://firebase.google.com/docs/crashlytics)
3. Check [FlutterFire Crashlytics](https://firebase.flutter.dev/docs/crashlytics/overview)
