# Step-by-Step Setup Instructions

Complete guide to build, install, and run the Canon DSLR direct-USB photobooth
on an Android TV box.

---

## Overview of steps

```
1. Install prerequisites on your Mac
2. Build the C++ sidecar binary (Docker → ARM32 and/or ARM64 Linux)
3. Run the Flutter app (debug) or build a release APK
4. Prepare the Android TV / Mini PC
5. Install the APK (release only — skip if using flutter run)
6. Connect the Canon camera (USB PTP)
7. Verify end-to-end
8. Troubleshooting
```

---

## Step 1 — Prerequisites (Mac)

### 1a. Docker Desktop

Download and install Docker Desktop from https://www.docker.com/products/docker-desktop

After install, open Docker Desktop and confirm it is running (whale icon in menu bar).

Verify in terminal:

```bash
docker --version
# Expected: Docker version 24.x or later
```

**If you are on an Intel Mac:** Docker will use QEMU to emulate ARM64. The
build will work but will be slower (~10–15 min). On Apple Silicon (M1/M2/M3)
the build is native and fast (~2–3 min).

### 1b. Flutter SDK

Confirm Flutter is installed and pointing at the correct version:

```bash
cd /Users/janakiram/photobooth/photobooth
flutter --version
flutter doctor
```

All items should show a green tick. Fix any issues flutter doctor reports before
continuing.

### 1c. Android SDK and ADB

ADB is needed to install the APK and inspect the device.

```bash
adb version
# Expected: Android Debug Bridge version 1.0.41 or later
```

If not installed, it ships with Android Studio or can be installed via
Homebrew:

```bash
brew install android-platform-tools
```

### 1d. Canon EDSDK

Confirm the EDSDK folder is present:

```bash
ls "/Users/janakiram/Downloads/EDSDK132021CD(13.20.21)/Linux/EDSDK/Library/ARM64/libEDSDK.so"
# Should print the file path without error
```

---

## Step 2 — Build the C++ sidecar binary

This step compiles the `canon-sidecar` Linux binary inside Docker (ARM32 and
ARM64) and bundles it with glibc + EDSDK. ARM32 is required for 32-bit Android
TV boxes (`armeabi-v7a`); ARM64 is for 64-bit kiosks.

### 2a. Run the build script

```bash
cd /Users/janakiram/photobooth/canon_sidecar
./build.sh
# This Mini PC only:
# SIDECAR_ARCHES=arm32 ./build.sh
```

What this does (automatically):
- Copies EDSDK headers and `libEDSDK.so` into the Docker build context
- Builds a Docker image using Ubuntu 20.04 ARM64
- Compiles `canon-sidecar` linked against EDSDK
- Collects all required `.so` files (`libc.so.6`, `libm.so.6`, `libpthread.so.0`,
  `libstdc++.so.6`, `libgcc_s.so.1`, `libusb-1.0.so.0`, `ld-linux-aarch64.so.1`)
- Copies the complete bundle to
  `photobooth/android/app/src/main/assets/canon_sidecar/<abi>/`

JNI executables go to `jniLibs/arm64-v8a/` and `jniLibs/armeabi-v7a/`.

### 2b. Verify the bundle

```bash
ls -lh photobooth/android/app/src/main/jniLibs/armeabi-v7a/
ls -lh photobooth/android/app/src/main/assets/canon_sidecar/armeabi-v7a/
```

---

## Step 3 — Build the Android APK

### 3a. Get Flutter dependencies

```bash
cd /Users/janakiram/photobooth/photobooth
flutter pub get
```

### 3b. Run the analyzer (zero errors required)

```bash
flutter analyze lib/
# Must complete with: No issues found!
```

Fix any errors before building.

### 3c. Build the release APK

Use the version-sync wrapper (required by this repo — do not use plain
`flutter build apk`):

```bash
cd /Users/janakiram/photobooth/photobooth

./scripts/flutter_with_version.sh build apk --release \
  --dart-define=CAMERA_SIDECAR_ENABLED=true \
  --dart-define=CAMERA_SIDECAR_URL=http://127.0.0.1:8791 \
  --dart-define=CAMERA_SIDECAR_LIVE_PREVIEW=true
```

Those `--dart-define` flags are **optional**. `CameraSidecarConfig` already
defaults to enabled, `http://127.0.0.1:8791`, and live preview on. Pass them
only when you need to override (for example a Pi host).

### 3d. Locate the APK

```bash
ls -lh /Users/janakiram/photobooth/photobooth/build/app/outputs/flutter-apk/app-release.apk
```

### 3e. Debug run (recommended while developing)

Do **not** use a release APK for day-to-day Pose work. From `photobooth/`, with
the box on ADB (USB or wireless):

```bash
cd /Users/janakiram/photobooth/photobooth
flutter pub get
flutter run --debug --no-enable-impeller
```

`--no-enable-impeller` is required on the 4GB Amlogic Mini PC / Android TV
boxes. Impeller is unreliable there (black or frozen Pose). Phones that render
Impeller correctly can omit the flag.

Wireless ADB example (port changes after each `adb tcpip`):

```bash
adb connect <box-ip>:<port>
flutter run --debug --no-enable-impeller -d <box-ip>:<port>
```

**What needs a full restart vs hot restart**

| Change | How to pick it up |
|---|---|
| Dart / Flutter Pose UI | Hot restart: press `R` in the Flutter terminal |
| Kotlin (`CanonSidecarService`, USB permission) | Stop `flutter run`, start it again |
| C++ sidecar, USB hook, JNI spawn, or `libcanon_sidecar.so` | Rebuild with `SIDECAR_ARCHES=arm32 ./build.sh` (32-bit box) or `./build.sh` (both ABIs), then a **full** `flutter run`. Hot reload / hot restart will **not** replace JNI or the sidecar binary. |

After a sidecar binary update, if Pose still talks to an old process:

```bash
adb shell am force-stop com.srisarani.fotozenai
# then flutter run again
```

---

## Step 4 — Prepare the Android TV box

### 4a. Enable Developer Options

On the Android TV box remote or settings screen:

1. Go to **Settings → Device Preferences → About**
2. Scroll to **Build** and press OK seven times until you see
   *"You are now a developer"*
3. Go back to **Settings → Device Preferences → Developer Options**
4. Enable **USB Debugging**

### 4b. Connect the box to your Mac

Connect an ADB cable (USB-A to USB-A, or USB-C depending on box model)
from the Android box to your Mac.

Alternatively, use ADB over Wi-Fi if the box is on the same network:

```bash
adb tcpip 5555          # once, while USB-connected
adb connect <box-ip-address>:<port>
```

The wireless port is not always `5555` (some boxes pick a high ephemeral port).
Use whatever `adb devices` shows.

### 4c. Confirm ADB connection

```bash
adb devices
```

Expected:
```
List of devices attached
192.168.x.x:5555    device       # (Wi-Fi ADB)
# or
XXXXXXXXXX          device       # (USB ADB)
```

If it shows `unauthorized`, check the box screen — it will ask you to allow
USB debugging from your Mac. Accept it.

### 4d. Check available disk space on the box

```bash
adb shell df /data
```

The APK is roughly 80–120 MB (sidecar bundle included). Confirm at least
200 MB free.

### 4e. Find the Canon camera USB Product ID

Connect the Canon EOS 200D II to the Android box via USB Micro-B cable.
Then run:

```bash
adb shell lsusb
```

Look for a line containing `04a9` (Canon vendor ID). Example:

```
Bus 001 Device 003: ID 04a9:32cb Canon, Inc. EOS 200D II
```

Note the product ID (`32cb` in this example). Then open:

```
photobooth/android/app/src/main/res/xml/device_filter.xml
```

Find the comment about confirming the EOS 200D II product ID and update it.
This is optional but good practice — the broad `vendor-id="1193"` entry
already works for the USB permission grant.

---

## Step 5 — Install the APK

### 5a. Uninstall any previous version

```bash
adb uninstall com.srisarani.fotozenai
```

(Ignore errors if not previously installed.)

### 5b. Install the new APK

```bash
adb install -r /Users/janakiram/photobooth/photobooth/build/app/outputs/flutter-apk/app-release.apk
```

Expected output:
```
Performing Streamed Install
Success
```

### 5c. Launch the app

```bash
adb shell am start -n com.srisarani.fotozenai/.MainActivity
```

---

## Step 6 — Connect the Canon camera

### 6a. Prepare the camera

Before connecting:

1. **Disable Auto Power Off**: Camera menu → Settings (wrench icon) →
   **Auto power off → Disable**
2. **Set to Manual mode**: Turn the mode dial to **M**
3. **Set USB connection mode**: Camera menu → Settings →
   **Communication settings → USB connection → PTP**
   *(Some firmware versions show this as "PC Connection" or skip this step
   if it is not present)*

### 6b. Connect via USB

Plug the Canon EOS 200D II Micro-B USB cable into one of the Android box's
USB-A ports.

### 6c. Grant USB permission

A system dialog will appear on the Android TV box screen:

```
Allow Fotozen AI to access Canon EOS 200D II?
[ ] Always open Fotozen AI when this device is connected
[Cancel]   [OK]
```

Select **OK** (and optionally tick "Always open" to avoid the dialog on
future reboots).

Android does **not** chmod `/dev/bus/usb/...` for the glibc sidecar. The app
opens the device with `UsbManager.openDevice()`, JNI fork+exec inherits that
fd, and `LD_PRELOAD` `libusb_open_hook.so` must wrap **`__open_2`** (not only
`open()`) so EDSDK/libusb reuse the permitted fd.

If no dialog appears, trigger it manually:

```bash
adb shell am broadcast \
  -a android.hardware.usb.action.USB_DEVICE_ATTACHED \
  -n com.srisarani.fotozenai/.MainActivity
```

---

## Step 7 — Verify end-to-end

### 7a. Watch the sidecar log in real time

```bash
adb logcat -s CanonSidecar:D canon:D
```

After granting USB permission you should see:

```
CanonSidecar: Extracting canon_sidecar assets ...
CanonSidecar: Extracted 10 files
CanonSidecar: Canon USB permission granted — launching sidecar
CanonSidecar: Starting canon-sidecar (attempt 1)
canon:        [sidecar] Canon EDSDK sidecar v1.0 starting
canon:        [sidecar] listening on 127.0.0.1:8791
canon:        [sidecar] attempting camera init...
canon:        [canon] camera ready
```

If you see `[canon] no camera found`, the camera is not detected via USB.
Check the cable and camera USB mode (Step 6a).

### 7b. Hit the health endpoint directly

```bash
adb shell curl http://127.0.0.1:8791/health
```

Expected:
```json
{"ok":true,"connected":true}
```

If you get `curl: command not found`, use:

```bash
adb shell "echo -e 'GET /health HTTP/1.0\r\n' | nc 127.0.0.1 8791"
```

### 7c. Test a live preview frame

```bash
adb shell curl -X POST "http://127.0.0.1:8791/camera/live-view"
# Expected: {"enabled":true,"woke":true,"holding":true}

adb shell curl -X POST "http://127.0.0.1:8791/camera/preview?download=1" \
  --output /sdcard/test_preview.jpg

adb pull /sdcard/test_preview.jpg /tmp/test_preview.jpg
open /tmp/test_preview.jpg
```

You should see a live view JPEG from the camera.

### 7d. Test a still capture

```bash
adb shell curl -X POST "http://127.0.0.1:8791/camera/capture?download=1" \
  --output /sdcard/test_capture.jpg \
  --max-time 45

adb pull /sdcard/test_capture.jpg /tmp/test_capture.jpg
open /tmp/test_capture.jpg
```

The shutter should fire on the camera and a full-resolution JPEG should appear
on your Mac.

### 7e. Run a full photobooth session in the app

Open the app on the Android TV box and run through the normal flow:

- Slideshow → Splash → Terms → Theme → Pose screen
- Confirm the live preview appears in the pose UI (same as it did with the Pi)
- Trigger a 4-shot Classic session and confirm all 4 shots capture successfully
- Confirm the strip composes and the QR share screen appears

---

## Step 8 — Troubleshooting

### Sidecar does not start (`no Canon DSLR found in USB device list`)

- The USB dialog was not shown or was dismissed — force it:
  ```bash
  adb shell am start -n com.srisarani.fotozenai/.MainActivity
  ```
  Then unplug and re-plug the USB cable.
- Confirm camera is in PTP mode (not MTP or Mass Storage).
- Try a different USB port on the box.
- Try the Canon OEM cable — third-party cables sometimes fail PTP negotiation.

### `/health` returns `connected: false` after permission granted

- Camera entered sleep mode: wake it (half-press shutter) and wait 5 s for
  the sidecar's retry loop to reconnect.
- Auto power-off is still enabled on the camera — disable it (Step 6a).
- Check `adb logcat -s CanonSidecar:D` for the EDSDK error code.
  Code `0x00000021` = device busy (camera in wrong mode).
  Code `0x00000083` = session already open (restart the app).

### Live preview shows but capture fails / times out

- Capture tries AF **Halfway** then **Completely**, then falls back to
  **NonAF Completely**. Manual (**M**) is still the most reliable kiosk mode
  if AF hunts in the dark.
- Check that the lens cap is off and the camera is not in video mode.
- Increase the capture timeout by editing `main.cpp`:
  change `g_camera.capture(30)` to `g_camera.capture(60)` and rebuild the
  sidecar (`SIDECAR_ARCHES=arm32 ./build.sh` on this Mini PC), then a full
  `flutter run`.

### Pose review is black / much darker than live preview

Live EVF is gain-boosted. The mechanical shutter JPEG uses still AE and is
often several stops darker indoors. Pose keeps the last EVF JPEG and uses it
for review when the still is far darker than that live frame. If review is
still empty:

- Confirm the box has **zero Camera2 cameras** (`adb logcat` / CameraX
  `availableCameras()`). Sidecar pose **must skip CameraX** or a later
  `resetAndInitializeCameras()` can wipe the captured still.
- Confirm capture returned a JPEG (`format=0x3801`), not CR2/CR3.

### `flutter run` is black or frozen on the Mini PC

Pass `--no-enable-impeller`. Do not rely on hot reload after native sidecar
changes.

### USB permission dialog appears on every reboot

This is normal on stock Android if `android.hardware.usb.action.USB_DEVICE_ATTACHED`
is not declared in the manifest with a matching device filter. The existing
manifest already has this declared. If the dialog still appears after reboot,
the box's USB permission persistence may need MDM configuration (device-owner
mode).

### Docker build fails on Intel Mac (slow or times out)

Docker uses QEMU to emulate ARM64 on Intel Macs, which can be slow.
Try increasing Docker Desktop memory to 8 GB:
Docker Desktop → Settings → Resources → Memory → 8 GB

Or build on an ARM64 Linux machine (Raspberry Pi 4 with 64-bit OS):
```bash
# On the Pi:
sudo apt install cmake build-essential patchelf libusb-1.0-0-dev
# Copy EDSDK and canon_sidecar/ to the Pi, then:
mkdir -p build && cd build
cmake /path/to/canon_sidecar -DCMAKE_BUILD_TYPE=Release
make -j4
```
Copy the binary and collect libraries manually (see `Dockerfile` for the list).

### App connects to old Pi instead of localhost

Sidecar defaults are already localhost. If Pose still hits the Pi, a ZenAI
admin `cameraSidecarHost` override is likely set. You can verify at runtime:

```bash
adb logcat -s flutter
# Look for lines containing "sidecar" — they will show the base URL being used.
```

If the ZenAI admin settings have a `cameraSidecarHost` set to the Pi IP,
those override the dart-defines. Update the admin settings to `127.0.0.1`.

---

## Quick reference — common commands

```bash
# Debug run (Mini PC / Android TV)
cd /Users/janakiram/photobooth/photobooth
flutter run --debug --no-enable-impeller

# Rebuild sidecar after C++ changes (32-bit Mini PC)
cd /Users/janakiram/photobooth/canon_sidecar && SIDECAR_ARCHES=arm32 ./build.sh
# Both ABIs:
# ./build.sh

# Then a full flutter run (not hot reload)
cd /Users/janakiram/photobooth/photobooth
flutter run --debug --no-enable-impeller

# Rebuild and reinstall release APK (dart-defines optional; defaults are on)
cd /Users/janakiram/photobooth/photobooth
./scripts/flutter_with_version.sh build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Watch live sidecar logs
adb logcat -s CanonSidecar:D canon:D

# Check sidecar health
adb shell curl http://127.0.0.1:8791/health

# Force-stop and restart the app
adb shell am force-stop com.srisarani.fotozenai
adb shell am start -n com.srisarani.fotozenai/.MainActivity

# Clear app data (resets extracted assets — useful after sidecar update)
adb shell pm clear com.srisarani.fotozenai
```
