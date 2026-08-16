# Photo Booth Application

A Flutter photo booth application with AI transformations, built using MVVM architecture.

## Repository layout

In this git repository, **this directory (`photobooth/`) is the Flutter project root** (`pubspec.yaml`, `lib/`, `android/`, `ios/`). Clone the repo, then run every Flutter/Dart command from here:

```bash
cd photobooth
flutter pub get
flutter run --debug --no-enable-impeller
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

Pose can use three sources, in this order on kiosk boxes:

1. **Canon EDSDK sidecar** (USB DSLR on `127.0.0.1:8791`) — live EVF JPEG + shutter stills. See [`../canon_sidecar/SETUP.md`](../canon_sidecar/SETUP.md).
2. **UVC / HDMI capture card** via the `uvccamera` plugin.
3. **Official Flutter `camera` plugin** (CameraX) for built-in / some USB webcams. Mini PCs with **zero Camera2 cameras** skip CameraX when sidecar pose is active.

- **Camera list**: Cameras are enumerated via `availableCameras()` from the `camera` package when Pose opens CameraX (includes built-in and external/USB cameras on supported devices).
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

2. Run the app (debug). From **`photobooth/`**, with the Android box on ADB:

```bash
flutter run --debug --no-enable-impeller
```

Sidecar dart-defines default **on** (`CAMERA_SIDECAR_ENABLED`, `CAMERA_SIDECAR_URL=http://127.0.0.1:8791`, `CAMERA_SIDECAR_LIVE_PREVIEW`). You do not need to pass them for a local Canon USB kiosk.

After **C++ / Kotlin / JNI** sidecar changes on a 32-bit Mini PC:

```bash
cd ../canon_sidecar
SIDECAR_ARCHES=arm32 ./build.sh
cd ../photobooth
flutter run --debug --no-enable-impeller
```

Hot reload does not replace `libcanon_sidecar.so`. Dart-only Pose fixes: press `R` (hot restart).

3. Build release APK (output under `build/app/outputs/flutter-apk/`). **Do not** use plain `flutter build apk` — it skips version sync:

```bash
./scripts/flutter_with_version.sh build apk --release
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
