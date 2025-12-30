# External Camera Troubleshooting Guide

## Issue: HP 960K Camera Not Showing in Camera Selection

If your external camera (HP 960K) is not appearing in the camera selection screen, follow these steps:

## Step 1: Check Camera Connection

1. **Physical Connection:**
   - Ensure the camera is properly connected to your iPad via USB
   - Try disconnecting and reconnecting the camera
   - Check if the camera requires external power (some cameras need a powered USB hub)

2. **iPad Recognition:**
   - Open the native Camera app on your iPad
   - Check if the external camera appears there
   - If it doesn't appear in the native Camera app, iOS may not recognize it as a video device

## Step 2: Refresh Camera List

1. **In the App:**
   - Tap the refresh button (circular arrow icon) in the top-right corner of the "Select Camera" screen
   - This will reload the camera list

2. **Restart the App:**
   - Close the app completely
   - Reconnect the camera
   - Reopen the app and navigate to the camera selection screen

## Step 3: Check Debug Logs

The app now includes debug logging. When you open the camera selection screen, check the console/logs for:

```
📷 Detected X camera(s):
  - Name: "...", Direction: ..., SensorOrientation: ...
```

This will show:
- How many cameras iOS detected
- The name and properties of each camera
- Whether the external camera is being detected but not displayed

### How to View Logs:

**From Terminal:**
```bash
flutter run -d "Janakiram's iPad"
# Watch the console output when you navigate to camera selection
```

**From Xcode:**
1. Open `ios/Runner.xcworkspace` in Xcode
2. Run the app from Xcode
3. View logs in the Xcode console (bottom panel)

## Step 4: iOS Camera Compatibility

Not all USB cameras are compatible with iOS. The camera must:

1. **Support USB Video Class (UVC):**
   - Most modern USB cameras support this
   - HP 960K should support UVC

2. **Be Recognized by iOS:**
   - iOS has stricter requirements than Android
   - Some cameras may work on Android but not iOS

3. **Use Supported Format:**
   - iOS requires specific video formats
   - The camera must provide a compatible video stream

## Step 5: Check Camera Name Detection

The app now has improved camera name detection. It will:
- Look for "HP" or "960" in the camera name
- Display "HP 960K Camera" if detected
- Show the raw camera name if available

If the camera appears with a generic name like "External Camera" or "Camera 2", it's still detected but iOS didn't provide a descriptive name.

## Step 6: Verify Camera Package Support

The app uses `camera: ^0.10.5+9`. External camera support depends on:
- The Flutter camera package version
- iOS version (iPadOS 13+ recommended)
- Camera hardware compatibility

## Step 7: Alternative Solutions

If the camera still doesn't appear:

1. **Check iPadOS Version:**
   - External camera support improved in iPadOS 13+
   - Update to the latest iPadOS version

2. **Try Different USB Connection:**
   - Use a different USB cable
   - Try a USB-C to USB-A adapter if needed
   - Some cameras work better with powered USB hubs

3. **Test with Other Apps:**
   - Try the native Camera app
   - Try other camera apps from the App Store
   - If it works in other apps but not this one, it's an app issue
   - If it doesn't work in any app, it's an iOS/hardware compatibility issue

4. **Check Camera Settings:**
   - Some cameras have settings that affect iOS compatibility
   - Check the camera's documentation for iOS/iPad compatibility

## Step 8: Report Debug Information

If the camera still doesn't work, collect this information:

1. **Camera Details:**
   - Model: HP 960K
   - Connection method: USB-C / USB-A / Adapter
   - Does it appear in native Camera app? Yes/No

2. **iPad Details:**
   - iPad model
   - iPadOS version
   - Available storage space

3. **App Logs:**
   - Copy the debug output showing detected cameras
   - Include any error messages

4. **Camera List:**
   - How many cameras appear in the app?
   - What are their names?

## Common Issues and Solutions

### Issue: Camera appears in native app but not in this app
**Solution:** The camera is detected by iOS but may have a different lens direction. Check the debug logs to see if it's detected with an unexpected direction.

### Issue: Camera works on Android but not iOS
**Solution:** This is likely an iOS compatibility issue. The camera may not fully support iOS video formats.

### Issue: Camera appears but shows generic name
**Solution:** This is normal. iOS doesn't always provide descriptive names for external cameras. The camera should still work.

### Issue: Camera appears but can't capture photos
**Solution:** This is a different issue. Check camera permissions and ensure the camera is properly initialized.

## Next Steps

1. Run the app with debug logging enabled
2. Check the console output when loading cameras
3. Try the refresh button after connecting the camera
4. Share the debug output if the issue persists

The debug logs will help identify if:
- The camera is detected but filtered out
- The camera has an unexpected name or direction
- iOS is not detecting the camera at all

