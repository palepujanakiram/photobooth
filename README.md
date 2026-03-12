# Photo Booth Application

A Flutter photo booth application with AI transformations, built using MVVM architecture.

## Features

- Theme selection
- Camera selection (front, back, and external cameras)
- Photo capture with zoom controls and orientation handling
- AI-powered image transformation
- Photo review and editing
- Printing support
- WhatsApp sharing

## Architecture

- **MVVM**: Models, ViewModels, and Views are separated; business logic lives in ViewModels.
- **State management**: Provider
- **Platform support**: iOS and Android (phones, tablets, Android TV)

## Camera Implementation

The app uses **only the official Flutter `camera` plugin**. There are no custom native camera plugins.

- **Camera list**: Cameras are enumerated via `availableCameras()` from the `camera` package when the user opens the Capture screen (includes built-in and external/USB cameras on supported devices).
- **Capture screen**:
  - **Preview**: Camera preview with orientation correction on Android (using display rotation from the platform and `RotatedBox` + `FittedBox` when needed). On Android TV OS 11, device orientation (0°, 90°, 180°, 270°) is supported via a platform channel that reads `WindowManager.getDefaultDisplay().rotation`.
  - **Zoom**: If the device supports it, zoom level is shown in an overlay and the user can change it (same style as a reference app).
  - **Capture**: Photos are taken at very high resolution (`ResolutionPreset.veryHigh`) and JPEG format. The raw file from the Flutter camera plugin is used (no resize or re-encode step).
  - **After capture**: An overlay shows captured photo details (resolution, width × height, file size).
- **Android**: A `photobooth/display` method channel provides `getRotation` so the Flutter side can correct preview orientation and lock capture orientation when appropriate.

## Getting Started

1. Install Flutter dependencies:

```bash
flutter pub get
```

2. Run the app:

```bash
flutter run
```

3. Build release APK (output: `photobooth-release.apk` in `build/app/outputs/flutter-apk/` and in `build/app/outputs/apk/release/`):

```bash
flutter build apk
```

The release APK name is set in `android/app/build.gradle` via the `appName` variable (default `photobooth`), producing `{appName}-release.apk` and `{appName}-debug.apk`.

## Project Structure

```
lib/
├── models/          # Data models
├── screens/         # Full-page screens (views + viewmodels)
├── services/        # Camera, API, file, error reporting, etc.
├── utils/           # Helpers, constants, logger
└── widgets/         # Reusable UI components
```

## Testing

Run tests with:

```bash
flutter test
```
