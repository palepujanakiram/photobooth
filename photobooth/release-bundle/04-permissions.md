# Permissions Audit — declared in code

Sourced directly from `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` as of `0.1.0+11`. For each permission: where it's declared, the user-visible string, and the justification to give a store reviewer if asked.

## Android

| Permission | Declared | User-visible string (current) | Recommended reviewer answer |
|---|---|---|---|
| `INTERNET` | ✅ | (none — normal permission) | "Required to upload the captured photo to FotoZen's AI processing server and to fetch the generated image back." |
| `POST_NOTIFICATIONS` | ✅ | "FotoZen AI would like to send you notifications" (system) | "Operational notifications to kiosk operators — payment confirmations, printer alerts. No marketing notifications." |
| `CAMERA` | ✅ | system prompt | "Core feature — captures the user's photo at the kiosk for AI transformation and printing." |
| `WRITE_EXTERNAL_STORAGE` (≤ Android 12) | ✅ `maxSdkVersion=32` | system | "Saving the generated photo to the kiosk's local cache for printing on Android 12 and below. Scoped storage is used on 13+." |
| `READ_EXTERNAL_STORAGE` (≤ Android 12) | ✅ `maxSdkVersion=32` | system | "Reading user-supplied photos when the user chooses 'Upload from gallery' on the kiosk on Android 12 and below." |
| `READ_MEDIA_IMAGES` (Android 13+) | ✅ | system | "Reading user-supplied photos for the 'Upload from gallery' flow on Android 13+." |

Hardware features declared with `required="false"` so the build runs on Android TV and tablets without all sensors:

- `android.hardware.usb.host` — USB camera support
- `android.hardware.camera`, `camera.autofocus`, `camera.external`
- `android.hardware.touchscreen` (false to allow Android TV install)
- `android.software.leanback` (Android TV)

> Engineer note: `usesCleartextTraffic="true"` is set on the `<application>`. **Set this to `false` for production** or restrict via `network-security-config.xml` whitelisting `fotozenai.fly.dev` only. Cleartext-permitting apps get flagged in Play's pre-launch report and can fail review.

## iOS

| Info.plist key | Declared | Current string | Recommended string |
|---|---|---|---|
| `NSCameraUsageDescription` | ✅ | "We need access to the external camera for photos." | **"FotoZen AI uses the camera to capture your photo for AI-styled portraits and printing."** *(softens "external camera" wording — current copy will confuse iOS reviewers running on a phone)* |
| `NSMicrophoneUsageDescription` | ✅ | "We need access to the microphone for external camera initialization." | **"Microphone access is requested by the OS during USB camera initialisation on kiosk hardware. The app does not record audio."** *(or, if the iOS build won't drive USB cameras, remove the key entirely)* |
| `NSPhotoLibraryAddUsageDescription` | ✅ | "This app needs access to save photos to your photo library." | **"FotoZen AI saves your AI-styled photo to your library when you choose to keep a digital copy."** |
| `NSPhotoLibraryUsageDescription` | ✅ | "This app needs access to your photo library to save and share photos." | **"FotoZen AI accesses your photo library to import a photo if you tap 'Upload from gallery', and to save the AI result if you choose to keep a copy."** |
| `ITSAppUsesNonExemptEncryption` | ❌ Missing | — | **Add `<key>ITSAppUsesNonExemptEncryption</key><false/>`** to skip the export-compliance prompt at every TestFlight upload. |

## Permissions NOT used (good — fewer reviewer questions)

| Permission | Status | Why mentioning |
|---|---|---|
| Location (precise / coarse / background) | ❌ Not requested | Sometimes flagged as "expected" for kiosk apps — confirm with reviewer that location is intentionally not used. |
| Bluetooth | ❌ | — |
| SMS / Phone | ❌ | — |
| Contacts | ❌ | — |
| Calendar | ❌ | — |
| Health / Motion | ❌ | — |
| `MANAGE_EXTERNAL_STORAGE` | ❌ | Avoided deliberately — Play's special-permission policy is strict. |
| `QUERY_ALL_PACKAGES` | ❌ | — |
| Background location | ❌ | — |
| Apple ATT (`NSUserTrackingUsageDescription`) | ❌ | App does not track users — leave this key absent. |
