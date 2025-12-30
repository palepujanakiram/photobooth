# Platform Support Guide

This document outlines the changes made to support iOS and Web platforms in addition to Android.

## Changes Made

### 1. Web Platform Support
- ✅ Created web folder structure using `flutter create --platforms=web`
- ✅ Updated `CameraService` to return `XFile` instead of `File` for web compatibility
- ✅ Updated `PhotoModel` and `TransformedImageModel` to use `XFile`
- ✅ Updated `photo_capture_viewmodel` to work with `XFile` on all platforms

### 2. iOS Platform Support
- ✅ iOS folder already exists with basic configuration
- ✅ Info.plist includes required camera permissions
- ✅ Camera permissions configured:
  - `NSCameraUsageDescription`
  - `NSPhotoLibraryUsageDescription`
  - `NSPhotoLibraryAddUsageDescription`

### 3. Remaining Work

#### API Client Updates
- [ ] Update `api_client.dart` to accept `XFile` or bytes instead of `File`
- [ ] Update `api_service.dart` to work with `XFile`
- [ ] Test API calls with web platform

#### Service Updates
- [ ] Update `share_service.dart` to handle web platform
- [ ] Update `print_service.dart` to handle web platform (may need web-specific implementation)
- [ ] Update `image_cache_service.dart` to handle web platform (use browser storage)

#### Platform-Specific Code
- [ ] Add conditional imports for `dart:io` in remaining files
- [ ] Add platform checks (`kIsWeb`) where needed
- [ ] Test camera functionality on iOS
- [ ] Test camera functionality on Web (requires HTTPS or localhost)

## Testing Checklist

### iOS
- [ ] Camera selection screen works
- [ ] Camera preview works
- [ ] Photo capture works
- [ ] Photo upload works
- [ ] Image transformation works
- [ ] Sharing works
- [ ] Printing works (if applicable)

### Web
- [ ] Camera selection screen works (requires HTTPS or localhost)
- [ ] Camera preview works
- [ ] Photo capture works
- [ ] Photo upload works
- [ ] Image transformation works
- [ ] Sharing works
- [ ] Printing works (browser print dialog)

## Known Limitations

### Web Platform
1. **Camera Access**: Requires HTTPS or localhost (secure context)
2. **File System**: No direct file system access, use browser storage
3. **Printing**: Uses browser print dialog instead of native printing
4. **Permissions**: Browser handles permissions differently than mobile

### iOS Platform
1. **Permissions**: Must be requested at runtime
2. **Camera**: May have different behavior than Android

## Running on Different Platforms

### Android
```bash
flutter run
```

### iOS
```bash
flutter run -d ios
```

### Web
```bash
flutter run -d chrome
# Or for localhost:
flutter run -d chrome --web-port=8080
```

## Dependencies

All dependencies in `pubspec.yaml` support iOS and Web:
- ✅ `camera: ^0.10.5+9` - Supports iOS and Web (via camera_web)
- ✅ `permission_handler: ^11.1.0` - Supports iOS and Web
- ✅ `share_plus: ^10.1.4` - Supports iOS and Web
- ✅ `printing: ^5.12.0` - Supports iOS and Web
- ✅ `webview_flutter: ^4.4.2` - Supports iOS and Web

