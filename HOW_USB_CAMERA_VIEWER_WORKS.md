# How USB Camera Viewer Works - Technical Analysis

## Overview

"USB Camera Viewer" successfully detects and uses the HP 960 4K camera because it uses **direct UVC (USB Video Class) access**, completely bypassing Android's Camera2 API.

## Why Our Current Approach Fails

### Current Implementation (Camera2 API)
```
USB Camera → Android HAL → Camera2 API → App
                ↓
         Camera ID "2" marked as "system only"
                ↓
         Access denied - cannot probe characteristics
                ↓
         ❌ Cannot access camera
```

### USB Camera Viewer Approach (UVC Direct)
```
USB Camera → USB Host API → UVC Protocol → App
                ↓
         Direct USB device communication
                ↓
         ✅ Can access camera directly
```

## Technical Details

### 1. USB Device Detection

**USB Camera Viewer:**
```kotlin
// Direct USB enumeration
val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
val devices = usbManager.deviceList

// Find UVC cameras (USB Video Class = 14)
for (device in devices.values) {
    for (i in 0 until device.interfaceCount) {
        val intf = device.getInterface(i)
        if (intf.interfaceClass == 14) { // UVC class
            // This is a UVC camera - can access directly
        }
    }
}
```

**Our Current Approach:**
```kotlin
// Relies on Camera2 API enumeration
val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
val cameraIds = cameraManager.cameraIdList  // Only returns 0, 1
// Camera "2" exists but is "system only" - cannot access
```

### 2. Video Stream Access

**USB Camera Viewer:**
- Opens USB device directly
- Sends UVC control requests (SET_CUR, GET_CUR)
- Receives isochronous video stream
- Decodes frames (MJPEG/YUV)
- Displays on Surface/Texture

**Our Current Approach:**
- Tries to open via Camera2 API
- Fails because camera is "system only"
- Cannot access video stream

### 3. Photo Capture

**USB Camera Viewer:**
- Captures frame from video stream
- Saves as JPEG/PNG
- No Camera2 API needed

**Our Current Approach:**
- Requires Camera2 ImageCapture
- Cannot access camera → cannot capture

## Implementation Options

### Option 1: UVCCamera Library (Recommended)

**Library:** `com.serenegiant:usb-camera` (GitHub: saki4510t/UVCCamera)

**Pros:**
- ✅ Mature, well-tested library
- ✅ Handles UVC protocol
- ✅ Preview and capture support
- ✅ Active maintenance

**Cons:**
- ❌ Requires JNI integration
- ❌ Additional dependency
- ❌ More complex setup

**Implementation Steps:**
1. Add library to `build.gradle`
2. Create `UvcCameraController.kt`
3. Implement USB permission handling
4. Integrate with Flutter via method channel

### Option 2: Custom UVC Implementation

**Pros:**
- ✅ Full control
- ✅ No external dependencies
- ✅ Customizable

**Cons:**
- ❌ Very complex
- ❌ Need to implement UVC protocol
- ❌ Time-consuming
- ❌ Error-prone

### Option 3: Try Camera "2" Directly (Current Attempt)

**What We're Doing:**
- Try to open camera "2" via Camera2 API
- Even though it's marked "system only"
- Native controller might have different permissions

**Pros:**
- ✅ Simple - no new dependencies
- ✅ Uses existing code
- ✅ Quick to test

**Cons:**
- ❌ May not work (system restriction)
- ❌ Depends on Android version/device
- ❌ Not guaranteed

## Recommended Solution: UVCCamera Library

### Step 1: Add Dependency

**File:** `android/app/build.gradle`
```gradle
dependencies {
    // UVCCamera library
    implementation 'com.serenegiant:common:1.5.20'
    implementation 'com.serenegiant:usb-camera:1.5.20'
}
```

### Step 2: Create UVC Controller

**File:** `android/app/src/main/kotlin/com/example/photobooth/UvcCameraController.kt`

```kotlin
import com.serenegiant.usb.UVCCamera
import android.hardware.usb.UsbDevice
import android.view.Surface

class UvcCameraController(private val context: Context) {
    private var mCamera: UVCCamera? = null
    private var mUsbDevice: UsbDevice? = null
    
    fun initialize(usbDevice: UsbDevice, result: MethodChannel.Result) {
        mUsbDevice = usbDevice
        try {
            mCamera = UVCCamera()
            mCamera?.open(usbDevice)
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.error("UVC_ERROR", "Failed to open UVC camera: ${e.message}", null)
        }
    }
    
    fun startPreview(surface: Surface, result: MethodChannel.Result) {
        try {
            mCamera?.setPreviewSize(1280, 720, UVCCamera.FRAME_FORMAT_YUYV)
            mCamera?.setPreviewDisplay(surface)
            mCamera?.startPreview()
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.error("PREVIEW_ERROR", "Failed to start preview: ${e.message}", null)
        }
    }
    
    fun capturePhoto(result: MethodChannel.Result) {
        // Capture frame from preview
        // Save as JPEG
    }
}
```

### Step 3: Integrate with Flutter

Update `MainActivity.kt` to handle UVC camera requests:
- Detect UVC cameras via USB enumeration
- Initialize UVC controller
- Return texture ID for preview
- Handle photo capture

## Why This Will Work

1. **Bypasses Camera2 API** - Direct USB access
2. **No System Restrictions** - USB permissions only
3. **Standard Protocol** - UVC is well-supported
4. **Proven Solution** - Used by many apps

## Testing Plan

1. ✅ Add UVCCamera library
2. ✅ Implement UVC controller
3. ✅ Test with HP 960 4K camera
4. ✅ Verify preview works
5. ✅ Verify photo capture works

## Next Steps

1. **Research UVCCamera Library** - Check latest version and compatibility
2. **Add Library** - Integrate into project
3. **Implement Controller** - Create UVC camera controller
4. **Flutter Integration** - Connect to Flutter side
5. **Test** - Verify with HP 960 4K camera

## References

- **UVCCamera Library**: https://github.com/saki4510t/UVCCamera
- **UVC Specification**: USB Video Class standard
- **Android USB Host**: https://developer.android.com/guide/topics/connectivity/usb/host
