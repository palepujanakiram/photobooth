# Photo Booth Application

A Flutter photo booth application with AI transformations, built using MVVM architecture.

## Repository layout

In this git repository, **this directory (`photobooth/`) is the Flutter project root** (`pubspec.yaml`, `lib/`, `android/`, `ios/`). Clone the repo, then run every Flutter/Dart command from here:

```bash
cd photobooth
flutter pub get
flutter run
```

The repository root only holds shared config (e.g. `.github/`, this README’s parent `README.md`); **do not** run `flutter` from the repo root.

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

From **`photobooth/`** (this folder):

1. Install Flutter dependencies:

```bash
flutter pub get
```

2. Run the app:

```bash
flutter run
```

3. Build release APK (output under `build/app/outputs/flutter-apk/`):

```bash
flutter build apk
```

The release APK name is set in `android/app/build.gradle` via the `appName` variable (default `photobooth`), producing `{appName}-release.apk` and `{appName}-debug.apk`.

## Project Structure

Paths below are relative to **`photobooth/`**:

```
lib/
├── models/          # Data models
├── screens/         # Full-page screens (views + viewmodels)
├── services/        # Camera, API, file, error reporting, etc.
├── utils/           # Helpers, constants, logger
└── widgets/         # Reusable UI components
```

## Testing

From **`photobooth/`**:

```bash
flutter test
```
