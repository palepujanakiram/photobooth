# Gallery Selection Feature

## 📸 Overview

Added a **gallery selection** option as a fallback when camera is not working properly. Users can now select photos from their device's photo gallery instead of capturing with the camera.

## 🎯 Purpose

This feature provides a workaround for:
- ✅ **Camera hardware issues** on Android TV or other devices
- ✅ **External camera compatibility problems**
- ✅ **Camera permission issues**
- ✅ **Testing the app flow** without needing a working camera
- ✅ **Users who prefer to use existing photos**

## 🏗️ Implementation

### **1. Backend: ViewModel Method**

Added `selectFromGallery()` method in `CaptureViewModel`:

```dart
// lib/screens/photo_capture/photo_capture_viewmodel.dart

/// Selects a photo from the device gallery
/// This is a fallback option when camera is not working properly
Future<void> selectFromGallery() async {
  // Opens device gallery
  final ImagePicker picker = ImagePicker();
  final XFile? imageFile = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1920,
    maxHeight: 1080,
    imageQuality: 95,
  );
  
  // Creates PhotoModel with selected image
  // Follows the same flow as captured photos
}
```

**Key Features:**
- Uses `image_picker` package (already in dependencies)
- Maintains the same photo quality (max 1920x1080, 95% quality)
- Creates a `PhotoModel` just like camera capture
- Integrates with error reporting system
- Full error handling with user-friendly messages

### **2. Frontend: UI Button**

Added gallery button next to the capture button:

```dart
// lib/screens/photo_capture/photo_capture_view.dart

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    // Gallery button (smaller, left side)
    CupertinoButton(
      onPressed: () => viewModel.selectFromGallery(),
      child: Icon(CupertinoIcons.photo),
    ),
    
    // Capture button (larger, main action)
    CupertinoButton(
      onPressed: () => viewModel.capturePhoto(),
      child: Icon(CupertinoIcons.camera),
    ),
  ],
)
```

**Visual Design:**
- 📷 **Capture button**: 80x80px circle, primary action
- 🖼️ **Gallery button**: 60x60px circle, secondary action with subtle border
- Both buttons show loading spinner when active
- Buttons disabled during processing

## 🔄 User Flow

### **Normal Camera Capture Flow**
```
1. User opens Photo Capture screen
2. Camera preview shows
3. User taps capture button 📷
4. Photo is captured
5. User continues to theme selection
```

### **New Gallery Selection Flow**
```
1. User opens Photo Capture screen
2. Camera has issues / user prefers gallery
3. User taps gallery button 🖼️
4. Device gallery/photos app opens
5. User selects existing photo
6. Photo is loaded into app
7. User continues to theme selection
```

Both flows converge at the same point after photo selection!

## 💡 Usage Examples

### **When to Use Gallery Selection?**

1. **Camera Not Working**
   ```
   Camera shows error → User taps gallery button → Selects photo → Continues
   ```

2. **External Camera Timeout**
   ```
   External camera hangs → User taps gallery button → Uses existing photo → Continues
   ```

3. **Testing/Development**
   ```
   Developer testing themes → Uses gallery → Faster testing → No camera setup needed
   ```

4. **User Preference**
   ```
   User has a good photo → Uses gallery → Applies AI transformation → Shares result
   ```

## 📊 Technical Details

### **Image Picker Configuration**

```dart
await picker.pickImage(
  source: ImageSource.gallery,      // Open gallery
  maxWidth: 1920,                    // Same as camera
  maxHeight: 1080,                   // Same as camera
  imageQuality: 95,                  // High quality (95%)
);
```

### **Photo Model Creation**

```dart
_capturedPhoto = PhotoModel(
  id: photoId,                       // UUID
  imageFile: imageFile,              // XFile from gallery
  capturedAt: DateTime.now(),        // Current timestamp
  cameraId: cameraId ?? 'gallery',   // Marked as 'gallery'
);
```

### **Error Reporting Integration**

```dart
// Logs gallery selection events
ErrorReportingManager.log('📂 Gallery selection started');
ErrorReportingManager.log('✅ Photo selected from gallery');

// Sets custom key to distinguish from camera capture
await ErrorReportingManager.setCustomKey('photo_source', 'gallery');

// Records any errors during selection
await ErrorReportingManager.recordError(
  exception,
  stackTrace,
  reason: 'Gallery selection failed',
  extraInfo: {'error': e.toString()},
);
```

## 🎨 UI Design

### **Layout**

```
┌─────────────────────────────┐
│      Camera Preview         │
│          or                 │
│      Preview Disabled       │
└─────────────────────────────┘

         ┌───────┐
         │ Debug │
         │ Info  │
         └───────┘

    🖼️        📷
  Gallery   Capture
  (60px)    (80px)

┌─────────────────────────────┐
│   Camera Switch Buttons     │
│  [Front] [Back] [External]  │
└─────────────────────────────┘
```

### **Visual Characteristics**

| Element | Size | Style | Color |
|---------|------|-------|-------|
| Gallery Button | 60x60px | Circle with subtle border | Semi-transparent surface |
| Capture Button | 80x80px | Solid circle | Primary surface color |
| Gallery Icon | 28px | `CupertinoIcons.photo` | Text color |
| Capture Icon | 40px | `CupertinoIcons.camera` | Text color |

## 🔧 Platform Support

### **iOS**
- ✅ Opens Photos app
- ✅ Supports iCloud photos
- ✅ Respects photo permissions

### **Android**
- ✅ Opens Gallery / Google Photos
- ✅ Works on phones, tablets, and Android TV
- ✅ Supports external storage

### **Android TV**
- ✅ Opens file picker or gallery app
- ✅ Works with remote control navigation
- ✅ Perfect fallback for camera issues

## 🧪 Testing

### **Test Cases**

1. **Happy Path**
   ```
   Tap gallery → Select photo → Verify preview → Tap continue → Success ✅
   ```

2. **Cancellation**
   ```
   Tap gallery → Cancel selection → App returns to camera screen → No error ✅
   ```

3. **Large Photo**
   ```
   Select 4K photo → Image resized to 1920x1080 → Continues normally ✅
   ```

4. **Permission Denied**
   ```
   Tap gallery → Permission denied → Error message shown → User can retry ✅
   ```

5. **No Photos Available**
   ```
   Tap gallery → Empty gallery → User informed → Returns to camera ✅
   ```

### **Testing on Android TV**

```bash
# Build and install APK
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk

# Test flow
1. Open app on Android TV
2. Navigate to Photo Capture screen
3. Use remote control to select gallery button
4. Navigate gallery with D-pad
5. Select photo with center button
6. Verify photo loads correctly
7. Continue with app flow
```

## 📈 Benefits

### **For Users**
- ✅ **Fallback option** when camera doesn't work
- ✅ **Flexibility** to use existing photos
- ✅ **Faster** than troubleshooting camera issues
- ✅ **Better UX** on devices with camera problems

### **For Developers**
- ✅ **Easier testing** without camera setup
- ✅ **Debugging aid** for theme transformations
- ✅ **Remote support** (users can try gallery if camera fails)
- ✅ **Analytics** via error reporting (`photo_source: 'gallery'`)

### **For Business**
- ✅ **Reduced support tickets** for camera issues
- ✅ **Higher conversion** (users don't abandon due to camera problems)
- ✅ **Better experience** on problematic devices
- ✅ **Wider device compatibility**

## 🔍 Error Handling

### **Scenarios Covered**

1. **User Cancels Selection**
   - No error shown
   - Returns to camera screen
   - Can try again

2. **Gallery Access Denied**
   - Error message: "Gallery Selection Failed: Permission denied"
   - User can grant permission in settings
   - Error logged to Crashlytics

3. **Image Load Failure**
   - Error message: "Failed to load selected image"
   - User can select different photo
   - Error logged with details

4. **Large File**
   - Automatically resized to max dimensions
   - Quality maintained at 95%
   - No error shown to user

## 📝 Code Changes Summary

### **Files Modified**

1. **`lib/screens/photo_capture/photo_capture_viewmodel.dart`**
   - ✅ Added `selectFromGallery()` method
   - ✅ Added error handling for gallery selection
   - ✅ Integrated with error reporting
   - ✅ Same flow as camera capture

2. **`lib/screens/photo_capture/photo_capture_view.dart`**
   - ✅ Added gallery button UI
   - ✅ Layout adjusted for two buttons
   - ✅ Loading state for gallery selection
   - ✅ Visual styling for secondary action

### **Dependencies Used**

- ✅ `image_picker: ^1.0.7` (already in pubspec.yaml)
- No new dependencies required!

## 🚀 How to Use

### **As a User**

1. **Open Photo Capture screen**
2. **Tap the gallery icon** (🖼️) on the left
3. **Select a photo** from your gallery
4. **Tap Continue** to proceed with theme selection

### **As a Developer**

```dart
// ViewModel usage
await viewModel.selectFromGallery();

// Check photo source
final photoSource = await ErrorReportingManager.getCustomKey('photo_source');
// Returns: 'gallery' or 'camera'
```

## 📊 Analytics & Monitoring

### **Tracked Events**

```dart
// Event: Gallery selection started
ErrorReportingManager.log('📂 Gallery selection started');

// Event: Photo selected successfully
ErrorReportingManager.log('✅ Photo selected from gallery');

// Custom key: Photo source
ErrorReportingManager.setCustomKey('photo_source', 'gallery');

// Photo ID and session tracking
ErrorReportingManager.setPhotoCaptureContext(
  photoId: photoId,
  sessionId: sessionId,
);
```

### **Firebase Crashlytics Dashboard**

You can track:
- How many users use gallery vs camera
- Gallery selection errors
- Success rate of gallery selections
- Most common error types

**Query Example:**
```
Custom Keys:
  photo_source = 'gallery'
  
Events:
  "📂 Gallery selection started" → count
  "✅ Photo selected from gallery" → count
```

## 🔮 Future Enhancements

Potential improvements:

1. **Multiple Photo Selection**
   ```dart
   // Select multiple photos at once
   final images = await picker.pickMultiImage();
   ```

2. **Photo Editing Before Upload**
   ```dart
   // Crop, rotate, adjust before continuing
   final edited = await editPhoto(selectedPhoto);
   ```

3. **Recent Photos Quick Access**
   ```dart
   // Show last 5 photos as thumbnails
   final recent = await getRecentPhotos(limit: 5);
   ```

4. **Camera Roll Preview**
   ```dart
   // Inline gallery view instead of system picker
   final photo = await showInlineGallery();
   ```

## ✅ Checklist

- [x] Gallery selection method implemented
- [x] UI button added and styled
- [x] Error handling implemented
- [x] Error reporting integrated
- [x] Loading states handled
- [x] User cancellation handled
- [x] Image resizing configured
- [x] Code compiles successfully
- [x] Documentation created

## 🎉 Summary

The gallery selection feature is **production-ready** and provides:

✅ **Seamless fallback** when camera fails  
✅ **Same app flow** as camera capture  
✅ **Full error tracking** via ErrorReportingManager  
✅ **Great UX** with clear visual design  
✅ **Platform support** for iOS, Android, and Android TV  

**Users can now complete the photo booth experience even when the camera isn't working!** 📸➡️🖼️
