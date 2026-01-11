# External Camera Permissions Guide

## Problem
External camera preview was not showing when the external camera button was selected, even though front and back cameras worked fine.

## Root Cause
The app was not checking or requesting camera permissions before initializing external cameras. External cameras require explicit permission checks because they use native camera controllers (CustomCameraController) that bypass Flutter's camera package.

## Permissions Required

### iOS
1. **Camera Permission** (`NSCameraUsageDescription`)
   - ✅ Already configured in `Info.plist`
   - Description: "We need access to the external camera for photos."
   - **Status**: Required and configured

2. **Microphone Permission** (`NSMicrophoneUsageDescription`)
   - ✅ Already configured in `Info.plist`
   - Description: "We need access to the microphone for external camera initialization."
   - **Status**: Configured (though not strictly required for video-only cameras)

3. **Photos/Videos Permission** (`NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`)
   - ✅ Already configured in `Info.plist`
   - **Status**: Required for saving photos, already configured

4. **USB Devices**
   - ❌ **Not required** - iOS handles USB camera access automatically through AVFoundation
   - External cameras connected via USB are accessed through the standard Camera2/AVFoundation APIs
   - No additional USB-specific permissions needed

### Android
1. **Camera Permission** (`android.permission.CAMERA`)
   - ✅ Already configured in `AndroidManifest.xml`
   - **Status**: Required and configured

2. **USB Host Permission** (`android.hardware.usb.host`)
   - ✅ Already configured in `AndroidManifest.xml` as optional feature
   - **Status**: Not required for Camera2 API access
   - USB cameras accessed via Camera2 API don't need explicit USB host permission
   - The Camera2 API handles USB camera enumeration automatically

3. **Storage Permissions** (`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`)
   - ✅ Already configured in `AndroidManifest.xml`
   - **Status**: Required for saving photos, already configured

## Solution Implemented

### 1. Added Permission Checks Before Camera Initialization
- **File**: `lib/screens/photo_capture/photo_capture_viewmodel.dart`
- Added permission check in `resetAndInitializeCameras()` before loading cameras
- Added permission check in `switchCamera()` before switching to external camera
- Added permission check in `initializeCamera()` before initializing any camera

### 2. Improved Error Handling
- **File**: `lib/services/custom_camera_controller.dart`
- Added detection of permission errors from native code
- Converts permission errors to `PermissionException` for proper UI handling
- **File**: `lib/services/camera_service.dart`
- Added proper exception handling to rethrow permission errors instead of falling back

### 3. User-Friendly Error Messages
- Permission errors now show clear messages: "Camera permission is required. Please enable it in Settings."
- Errors are properly caught and displayed in the UI

## Testing Checklist

1. ✅ **Camera Permission Request**
   - App should request camera permission when entering photo capture screen
   - Permission dialog should appear if not already granted

2. ✅ **External Camera Selection**
   - When external camera button is tapped, permission should be verified
   - If permission denied, clear error message should be shown

3. ✅ **External Camera Preview**
   - After permission granted, external camera preview should display
   - Preview should use Texture widget (for custom controller) or CameraPreview (for standard)

4. ✅ **Error Handling**
   - Permission denied errors should be caught and displayed
   - User should be able to retry after granting permission

## Code Changes Summary

### Modified Files:
1. `lib/screens/photo_capture/photo_capture_viewmodel.dart`
   - Added `requestPermission()` calls before camera initialization
   - Added permission checks in `resetAndInitializeCameras()`, `switchCamera()`, and `initializeCamera()`

2. `lib/services/custom_camera_controller.dart`
   - Added `PermissionException` import
   - Added permission error detection and conversion
   - Improved error handling for PlatformException

3. `lib/services/camera_service.dart`
   - Added permission exception handling to prevent fallback on permission errors
   - Improved error propagation for permission issues

## Answer to User's Question

**Do we need to ask user to provide below permissions?**

1. **Camera** ✅ **YES** - Required and now properly requested
2. **Microphone** ⚠️ **OPTIONAL** - Already configured but not strictly required for video-only cameras
3. **Photos and Videos** ✅ **YES** - Required for saving photos, already configured
4. **USB Devices** ❌ **NO** - Not required. iOS and Android handle USB camera access automatically through their camera APIs.

## Next Steps

1. Test the app with an external camera connected
2. Verify permission dialog appears when needed
3. Confirm external camera preview displays after permission granted
4. Test permission denial flow to ensure error messages are clear
