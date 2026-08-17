# Fotozen AI — Debug & Release Build Guide

**Direct Canon USB (Android TV Mini PC)**

Use these builds so **direct Canon USB** is the default. The app uses Canon **EDSDK** on the Mini PC to show Pose live preview and fire the shutter in software — no Raspberry Pi and no HDMI capture card.

Run Flutter commands from `photobooth/` unless noted.

---

## 0. One-time / after C++ sidecar changes

Only needed if you changed `canon_sidecar/` or JNI spawn:

```bash
cd /Users/janakiram/photobooth/canon_sidecar
SIDECAR_ARCHES=arm32 ./build.sh
```

Then a **full** Flutter install (not hot reload).

---

## 1. GSM (required so backend does not send the app to a Pi)

On this kiosk in ZenAI / GSM:

- `cameraConnectionMode` = **`direct`**
- Leave Pi host unused (or ignore it; `direct` overrides it)

Without that, an old Pi IP can still be inferred if the mode field is empty.

---

## 2. Camera settings for Direct Canon EDSDK

The sidecar talks to the camera over **USB PTP**. It then programmatically:

- Turns on live view and routes EVF to the PC (`Evf_Mode` + `Evf_OutputDevice = PC`)
- Polls JPEG frames for Pose (`POST /camera/preview`)
- Fires the shutter and downloads a JPEG (`POST /camera/capture`)

You do **not** start live view or press the shutter by hand. You only put the body in a USB-PC state the SDK can control.

### 2a. Menu and dial (do this before plugging USB)

| Setting | Set to | Why |
|---|---|---|
| **USB connection** | **PTP** (or **PC** / **PC connection**) | EDSDK needs PTP. Not MTP, Print/MTP, or Mass storage. |
| **Auto power off** | **Disable** | Sleep drops the USB session (`connected: false`). |
| **Mode dial** | **M** (Manual stills) | Most reliable for programmatic AF + shutter. Not movie / video. |
| **Shooting mode** | **Stills** (photo) | Video mode blocks still capture. |
| Lens cap | **Off** | AF and exposure fail with the cap on. |

**USB menu path (typical EOS / Rebel, including 200D II / SL3):**

1. Press **Menu**.
2. Open the **wrench / Set-up** tab.
3. **Communication settings** (sometimes under **Wi-Fi / Bluetooth**).
4. **USB connection** → **PTP**.

If the body has no USB connection item, it usually defaults to PTP when plugged into a PC — leave it.

Other labels you may see: **PC connection**, **PC**, **PTP/MTP** → choose **PTP** or **PC**.

### 2b. Cable: USB to the Mini PC (not a Pi)

1. Use the **Canon USB cable** (camera Mini-B or Micro-B → USB-A).
2. Plug USB-A into a **USB port on the Android TV Mini PC** (the box running Fotozen).
3. Do **not** plug that cable into a Raspberry Pi, a hub that only goes to the Pi, or a laptop running EOS Utility (only one host can own PTP).
4. **HDMI is not required** for this path. Pose preview is USB EVF over EDSDK, not a capture card.

### 2c. Android USB permission (once per camera / reboot)

When the camera is attached, the TV should show:

```text
Allow Fotozen AI to access Canon …?
[ ] Always open Fotozen AI when this device is connected
[Cancel]   [OK]
```

Select **OK**. Tick **Always open** if you want to skip the dialog after reboot.

If no dialog appears: unplug/replug USB, or:

```bash
adb shell am start -n com.srisarani.fotozenai/.MainActivity
```

### 2d. Recommended (kiosk reliability)

- Full battery, or dummy battery / AC coupler.
- AF: One-Shot is fine in decent light; in a dark booth **M** + less hunting is more reliable (sidecar tries Halfway → Completely AF, then Non-AF shutter).
- Image quality on the body can stay JPEG; the sidecar requests **Large JPEG Fine** for download.
- Do not open the camera in playback-only with USB busy on another computer.

### 2e. Do not use these camera modes

| Avoid | What happens |
|---|---|
| MTP / Mass storage | Sidecar cannot open an EDSDK session (`device busy` / no camera). |
| Movie / video dial | Live view or capture times out. |
| Auto power off still on | Preview dies after a few minutes. |
| USB to Pi **and** Mini PC | Wrong host; Pose talks to localhost EDSDK on the TV box. |

---

## 3. Debug (day-to-day)

Impeller **must** be off on this box. Sidecar dart-defines already default to localhost USB; `CAMERA_CONNECTION_MODE=direct` makes that explicit even if GSM mode is blank.

### Run on the box

```bash
cd /Users/janakiram/photobooth/photobooth
flutter pub get
flutter run --debug --no-enable-impeller \
  --dart-define=CAMERA_CONNECTION_MODE=direct
```

### Build a debug APK

```bash
cd /Users/janakiram/photobooth/photobooth
flutter pub get
./scripts/flutter_with_version.sh build apk --debug --no-enable-impeller \
  --dart-define=CAMERA_CONNECTION_MODE=direct
```

**Output**

- `photobooth/build/app/outputs/flutter-apk/app-debug.apk`
- or `photobooth-debug.apk` depending on Gradle naming

**Install**

```bash
adb install -r photobooth/build/app/outputs/flutter-apk/photobooth-debug.apk
# if that path is missing:
adb install -r photobooth/build/app/outputs/flutter-apk/app-debug.apk
```

**After install**

```bash
adb shell am force-stop com.srisarani.fotozenai
adb shell am start -n com.srisarani.fotozenai/.MainActivity
```

---

## 4. Release (kiosk APK)

Do **not** use plain `flutter build apk`. Release must sync version + Bugsnag key, and **must** disable Impeller or Pose can be blank/frozen.

Put `BUGSNAG_API_KEY` in `photobooth/.env` (copy from `.env.example` if needed).

```bash
cd /Users/janakiram/photobooth/photobooth
flutter pub get
./scripts/flutter_with_version.sh build apk --release --no-enable-impeller \
  --dart-define=CAMERA_CONNECTION_MODE=direct
```

**Output**

- `photobooth/build/app/outputs/flutter-apk/photobooth-release.apk`
- or `app-release.apk`

**Install** (uninstall debug first if signatures conflict):

```bash
adb uninstall com.srisarani.fotozenai
adb install -r photobooth/build/app/outputs/flutter-apk/photobooth-release.apk
adb shell am start -n com.srisarani.fotozenai/.MainActivity
```

Optional dart-defines (already the code defaults; only needed to override):

- `CAMERA_SIDECAR_ENABLED=true`
- `CAMERA_SIDECAR_URL=http://127.0.0.1:8791`
- `CAMERA_SIDECAR_LIVE_PREVIEW=true`

---

## 5. Confirm preview and programmatic snap

1. Camera settings from **section 2** applied; USB into the Mini PC.
2. USB permission granted.
3. Open Pose — you should see Canon EVF (software live view), not HDMI/UVC / “Starting camera…”.
4. Take a photo in the app — the body should fire by itself (EDSDK shutter), then preview should resume.

**USB enumerated:**

```bash
adb shell lsusb
```

Look for Canon vendor **`04a9`**, for example `ID 04a9:32cb Canon, Inc. EOS 200D II`.

**Sidecar healthy** (app running):

```bash
adb shell curl http://127.0.0.1:8791/health
```

Expect `"ok":true,"connected":true`.

**Logs:**

```bash
adb logcat -s CanonSidecar:I CanonUsbPerm:I flutter:I
```

Look for `camera ready`, live view armed, and `POSE using Canon USB EVF live preview`.

EDSDK error **`0x00000021`** = device busy (wrong USB mode or another PC holds the session). **`0x00000083`** = session already open (force-stop the app and retry).

---

## Do not

| Command | Why |
|---|---|
| `flutter build apk` (no wrapper) | Skips version sync; release also skips Bugsnag key |
| Release **without** `--no-enable-impeller` | Blank/frozen Pose on this Mini PC |
| Hot reload after C++/JNI changes | Old sidecar stays running |

**Pi booths:** omit `CAMERA_CONNECTION_MODE=direct` and set GSM `cameraConnectionMode=pi` plus sidecar host/port.
