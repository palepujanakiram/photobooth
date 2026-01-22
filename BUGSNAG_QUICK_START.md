# Bugsnag Integration - Quick Start

## ✅ Setup Complete!

Bugsnag has been added to your app alongside Firebase Crashlytics.

## 🎯 Configuration

**API Key**: `73ebb791c48ae8c4821b511fb286ca23`

**Services Active**:
- ✅ Firebase Crashlytics
- ✅ Bugsnag

## 📊 How It Works

```
Any error in your app
        ↓
ErrorReportingManager
        ↓
    ┌───┴───┐
    ↓       ↓
Crashlytics Bugsnag
```

**One API, Two Services!**

## 🚀 Usage

### **Log Events:**
```dart
ErrorReportingManager.log('User started photo capture');
```

### **Report Errors:**
```dart
ErrorReportingManager.recordError(
  exception,
  stackTrace,
  reason: 'Photo capture failed',
  extraInfo: {'camera_id': 'external_123'},
);
```

### **Set Custom Data:**
```dart
await ErrorReportingManager.setCustomKeys({
  'user_type': 'premium',
  'camera_id': 'external_123',
});
```

## 📱 Where to View

### **Bugsnag Dashboard:**
https://app.bugsnag.com/

### **Firebase Crashlytics:**
Firebase Console → Crashlytics

**Both dashboards show the same errors!**

## 🧪 Test It

```bash
# 1. Build app
flutter clean
flutter pub get
flutter build apk --release

# 2. Install and run
adb install build/app/outputs/flutter-apk/app-release.apk

# 3. Trigger an error
# (e.g., try photo capture with wrong camera)

# 4. Check both dashboards
# - app.bugsnag.com
# - Firebase Console
```

## ✨ Key Features

**Breadcrumbs:**
```
📸 Photo capture started
⏱️ Timeout after 8 seconds
❌ Capture failed
```

**Custom Metadata:**
```
camera_id: external_123
printer_ip: 192.168.1.100
photo_source: gallery
```

**User Tracking:**
```
User ID: user_12345
Device: Android TV
Version: 0.1.0+3
```

## 🔧 Enable/Disable

### **Both Services:**
```dart
await ErrorReportingManager.setEnabled(true);  // On
await ErrorReportingManager.setEnabled(false); // Off
```

### **Individual Services:**
```dart
// In main.dart initialization
await ErrorReportingManager.initialize(
  enableCrashlytics: true,  // Toggle Crashlytics
  enableBugsnag: true,      // Toggle Bugsnag
);
```

## 📈 Benefits

| Benefit | Description |
|---------|-------------|
| **Redundancy** | If one service is down, you have the other |
| **Best of Both** | Crashlytics (Google) + Bugsnag (independent) |
| **No Code Changes** | Use ErrorReportingManager for both |
| **Easy to Switch** | Enable/disable either service anytime |

## 🔍 What You Get

### **In Both Dashboards:**
- ✅ All app errors
- ✅ Stack traces
- ✅ Breadcrumb trails
- ✅ Custom metadata
- ✅ User information
- ✅ Device details
- ✅ Release tracking

## 📊 Monitor

### **Check Daily:**
- New critical errors
- Error spike alerts

### **Check Weekly:**
- Error trends
- Release stability
- User impact

## 💡 Pro Tips

1. **Compare Data**: Check both dashboards to validate errors
2. **Set Up Alerts**: Configure Bugsnag email/Slack notifications
3. **Use Custom Keys**: Add context to every error
4. **Track Breadcrumbs**: Log user journey before errors
5. **Privacy First**: Let users opt-out if needed

## 🎉 Summary

**Status**: ✅ Production Ready

**What Changed**:
- Added `bugsnag_flutter` package
- Created `BugsnagErrorReporter`
- Updated `ErrorReportingManager`
- Integrated in `main.dart`

**Result**: All errors now go to **both** Crashlytics and Bugsnag automatically!

---

**No code changes needed!** Just use `ErrorReportingManager` as before. 🚀
