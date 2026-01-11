# UVC Direct Access Implementation Guide

## How USB Camera Viewer Works

The "USB Camera Viewer" app uses **direct UVC (USB Video Class) access** to bypass Android's Camera2 API limitations. Here's how:

### Key Differences

| Approach | Camera2 API (Current) | UVC Direct Access (USB Camera Viewer) |
|----------|----------------------|--------------------------------------|
| **Detection** | Relies on Android enumeration | Direct USB device enumeration |
| **Access** | Via Camera2 API | Direct USB device communication |
| **Preview** | Camera2 Surface/Texture | Direct video stream from USB |
| **Capture** | Camera2 ImageCapture | Direct frame capture from USB stream |
| **Limitations** | Requires Camera2 ID | Works even without Camera2 ID |
| **Complexity** | Medium | High (requires native code) |

## Technical Implementation

### 1. USB Device Detection
```kotlin
// Direct USB enumeration (not via Camera2)
val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
val devices = usbManager.deviceList

// Find UVC cameras (class 14)
for (device in devices.values) {
    if (isUvcCamera(device)) {
        // Request USB permission
        // Open USB device directly
    }
}
```

### 2. UVC Protocol Communication
- **Control Requests**: Set/get camera settings (brightness, contrast, etc.)
- **Isochronous Transfers**: Stream video data from camera
- **Frame Format**: Usually MJPEG or YUV from USB camera

### 3. Video Stream Processing
- Receive video frames via USB isochronous transfers
- Decode frames (MJPEG or YUV)
- Display on Surface/Texture
- Capture frames for photos

## Implementation Options

### Option 1: Use Existing Library (Recommended)
**Android-UVC-Camera** (open source):
- GitHub: `https://github.com/saki4510t/UVCCamera`
- Provides UVC camera access for Android
- Includes preview and capture functionality
- Requires JNI integration

### Option 2: Use Flutter Plugin
**flutter_uvc_camera** (if available):
- Flutter plugin for UVC cameras
- May need modifications for your use case

### Option 3: Custom Implementation
- Use libuvc (C library)
- Create JNI bindings
- Implement UVC protocol in native code
- Most complex but most control

## Recommended Approach: UVCCamera Library

### Step 1: Add UVCCamera Library

Add to `android/app/build.gradle`:
```gradle
dependencies {
    implementation 'com.serenegiant:common:1.5.20'
    implementation 'com.serenegiant:usb-camera:1.5.20'
}
```

### Step 2: Create UVC Camera Controller

Create `android/app/src/main/kotlin/com/example/photobooth/UvcCameraController.kt`:
```kotlin
class UvcCameraController {
    private var mCameraHelper: UVCCamera? = null
    
    fun initialize(usbDevice: UsbDevice): Boolean {
        // Request USB permission
        // Initialize UVCCamera
        // Set preview surface
        return true
    }
    
    fun startPreview(surface: Surface) {
        mCameraHelper?.setPreviewSize(1280, 720, UVCCamera.FRAME_FORMAT_YUYV)
        mCameraHelper?.startPreview()
    }
    
    fun capturePhoto(): ByteArray? {
        // Capture frame from preview
        return mCameraHelper?.captureStillImage()
    }
}
```

### Step 3: Integrate with Flutter

Create method channel to:
- List UVC cameras
- Initialize UVC camera
- Start preview (return texture ID)
- Capture photo

## Implementation Steps

### Phase 1: Add UVCCamera Library ✅
1. Add dependency to `build.gradle`
2. Sync project

### Phase 2: Create UVC Controller ✅
1. Create `UvcCameraController.kt`
2. Implement USB permission handling
3. Implement preview functionality
4. Implement photo capture

### Phase 3: Flutter Integration ✅
1. Create method channel
2. Add Flutter-side helper
3. Update camera service to use UVC when Camera2 fails

### Phase 4: Testing ✅
1. Test with HP 960 4K camera
2. Verify preview works
3. Verify photo capture works

## Advantages of UVC Direct Access

✅ **Works without Camera2 ID** - Bypasses Android enumeration
✅ **More Control** - Direct access to camera settings
✅ **Reliable** - Doesn't depend on Android version/device
✅ **Standard Protocol** - UVC is well-documented

## Disadvantages

❌ **Complex** - Requires native code and JNI
❌ **Library Dependency** - Need to integrate UVCCamera library
❌ **Platform Specific** - Android only (iOS uses different approach)
❌ **More Code** - Additional implementation and maintenance

## Next Steps

1. **Research UVCCamera Library** - Check compatibility and features
2. **Add Library** - Integrate into Android project
3. **Implement UVC Controller** - Create native controller
4. **Flutter Integration** - Connect to Flutter side
5. **Test** - Verify with HP 960 4K camera

## References

- **UVCCamera Library**: `https://github.com/saki4510t/UVCCamera`
- **Android UVC Documentation**: `https://source.android.com/docs/core/camera/external-usb-cameras`
- **UVC Specification**: USB Video Class standard
