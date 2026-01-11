# USB Camera Troubleshooting Guide

## Problem: External Camera Not Showing Preview

When selecting the external camera button, you see an error:
> "External camera 'HP 4K Streaming Webcam' is not accessible. The camera may need time to initialize or may require additional setup."

## Root Cause

The USB camera is **detected** by the app but **doesn't have a Camera2 ID** assigned by Android. This means:
- ✅ USB camera is physically connected and detected
- ✅ App can see the camera via USB enumeration
- ❌ Android's Camera2 API hasn't enumerated it yet (no Camera2 ID)
- ❌ App cannot access it without a Camera2 ID

## Why This Happens

1. **Enumeration Delay**: Android needs time to enumerate USB cameras and assign Camera2 IDs
2. **System-Only Devices**: Some cameras are enumerated but marked as "system only" and not accessible to apps
3. **Driver Issues**: The camera may not have proper UVC drivers loaded
4. **Compatibility**: The camera might not be fully UVC-compliant

## Solutions

### Solution 1: Wait and Retry (Automatic)
The app now automatically retries 3 times with delays:
- Attempt 1: Immediate
- Attempt 2: After 4 seconds
- Attempt 3: After 6 seconds

**Action**: Just wait a few seconds and tap the external camera button again.

### Solution 2: Disconnect and Reconnect
1. Disconnect the USB camera
2. Wait 5 seconds
3. Reconnect the camera
4. Wait 5-10 seconds for Android to enumerate it
5. Try selecting the external camera again

### Solution 3: Check Camera Compatibility
The camera must be:
- ✅ **UVC-compliant** (USB Video Class)
- ✅ **Properly powered** (some cameras need external power or powered USB hub)
- ✅ **Connected via USB OTG** (if using a phone/tablet)

### Solution 4: Check Android Version
- **Android 10+**: May have stricter USB camera access requirements
- **Some devices**: May not support external USB cameras at all

## Technical Details

### What the Logs Show

```
⚠️ Access denied for camera 2: CAMERA_ERROR (3): getCameraCharacteristics:1107: 
Unable to retrieve cameracharacteristics for system only device 2:
```

This means:
- Camera ID "2" exists in the system
- But it's marked as "system only" - not accessible to apps
- This is a **system-level limitation**, not an app bug

### Camera2 ID Enumeration

Android's Camera2 API enumerates cameras in this order:
- **0**: Back camera (built-in)
- **1**: Front camera (built-in)
- **2+**: External cameras (if enumerated)

If the USB camera doesn't get a Camera2 ID, it can't be accessed via Camera2 API.

## Current Implementation

### What We're Doing

1. **Detection**: Using `UsbManager` to detect USB cameras
2. **Probing**: Trying to find Camera2 IDs for USB cameras
3. **Retry Logic**: Automatically retrying with delays
4. **Error Handling**: Showing clear error messages

### Limitations

- **Cannot force** Android to enumerate a camera
- **Cannot access** cameras without Camera2 IDs
- **Cannot bypass** "system only device" restrictions

## Future Improvements

### Option 1: UVC Direct Access
Use a library like `libuvc` to access USB cameras directly, bypassing Camera2 API:
- ✅ Works even without Camera2 ID
- ❌ Requires native code implementation
- ❌ More complex

### Option 2: Wait for Camera2 Enumeration
Add a background service that periodically checks for new Camera2 IDs:
- ✅ Automatic detection
- ❌ Still requires Camera2 ID

### Option 3: User Notification
Show a notification when USB camera is detected but not yet accessible:
- ✅ Better UX
- ❌ Doesn't solve the root problem

## Testing Checklist

1. ✅ Connect USB camera
2. ✅ Wait 10-15 seconds after connection
3. ✅ Check if camera appears in Camera2 API
4. ✅ Try selecting external camera button
5. ✅ If error, wait 5 seconds and retry
6. ✅ If still fails, disconnect/reconnect camera

## Known Issues

- **HP 960 4K Camera**: May need powered USB hub
- **Android 10+**: Stricter USB access requirements
- **Some devices**: Don't support external cameras at all

## Workaround

If the camera doesn't get a Camera2 ID:
1. Try a different USB cable
2. Use a powered USB hub
3. Try on a different Android device
4. Check if the camera works in other apps (like Camera app)
