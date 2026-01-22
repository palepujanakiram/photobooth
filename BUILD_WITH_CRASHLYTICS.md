# Build with Crashlytics Debugging

## Quick Build Command
```bash
flutter build apk --release
```

## What's Been Added

### Comprehensive Crashlytics Logging
The app now logs detailed information to Firebase Crashlytics at every step of the photo capture process:

1. **Before Capture Attempt**
   - Camera readiness state
   - Controller type (custom vs standard)
   - Preview status
   - Device ID and texture ID

2. **During Capture**
   - Service layer logs
   - Custom controller logs
   - Native platform calls

3. **On Timeout (8-10 seconds)**
   - Explicit timeout detection
   - Full state dump
   - Platform information
   - Stack trace

4. **On Error**
   - Error type and message
   - Camera state at time of error
   - Full stack trace
   - Device information

## Viewing Logs in Firebase Console

### 1. Access Crashlytics
```
Firebase Console → Your Project → Crashlytics
```

### 2. View Issues
- Go to "Issues" tab
- Filter by "Non-fatals" to see captured errors
- Sort by "Latest" to see most recent

### 3. Click on an Issue to See:
- **Custom Keys**: Camera state, device info, controller state
- **Breadcrumb Logs**: Sequence of events leading to error
- **Stack Trace**: Exact location of error
- **Device Details**: Android TV model, OS version
- **Occurrence Count**: How many times it happened

### 4. Look for These Specific Issues:
- "Photo capture timed out after 10 seconds"
- "Custom controller takePicture failed"
- "Camera not ready for photo capture"
- "Native takePicture returned failure"

## Key Custom Keys to Check

When viewing an error in Crashlytics, check these keys:

| Key | What It Tells You |
|-----|-------------------|
| `timeout_occurred` | Was this a timeout error? |
| `capture_deviceId` | Which camera was being used |
| `capture_isPreviewRunning` | Was preview working? |
| `native_takePicture_isInitialized` | Was camera initialized? |
| `camera_direction` | Was it an external camera? |

## Expected Behavior

### If Timeout Occurs:
1. User taps capture button
2. Spinner shows for 8-10 seconds
3. Error message appears on screen
4. **Crashlytics logs the full state**
5. User can dismiss error and try again

### In Crashlytics Console:
- You'll see a "Photo capture timed out" issue
- Click on it to see all the debug information
- Check the custom keys to understand camera state
- View breadcrumb logs to see exact flow

## Troubleshooting Tips

### No Logs Appearing?
- Ensure Firebase is configured correctly
- Check internet connection on Android TV
- Logs may take a few minutes to appear in console
- Try force-closing and reopening the app

### Want to See More Details?
- All logs also appear in LogCat (but you don't have access)
- Crashlytics is now the primary debugging tool
- Non-fatal errors are recorded even if app doesn't crash

## Testing Steps

1. Build and deploy APK to Android TV
2. Open app and navigate to camera selection
3. Select external camera (if available)
4. Wait for preview to appear
5. Tap capture button
6. Wait for timeout or error
7. Check Firebase Crashlytics console after 2-5 minutes

## What You'll Learn

The Crashlytics logs will tell you:
- ✅ Is the camera initializing properly?
- ✅ Is the preview actually running?
- ✅ Where exactly does the capture fail?
- ✅ Is it a timeout or immediate error?
- ✅ What state is the camera in when it fails?
- ✅ Is it specific to external cameras?

This replaces the need for LogCat access! 🎉
