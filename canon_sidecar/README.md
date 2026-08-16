# Canon DSLR Direct USB — Android Migration

## Problem

The current setup uses a **Raspberry Pi** as an intermediary between the Flutter
app and the Canon EOS 200D II camera. The Pi runs a process (`fotozen-sidecar`)
that holds the USB connection to the camera and exposes an HTTP API. The Flutter
app calls that API over the local network.

**Goal:** Remove the Pi. Connect the Canon camera directly to an **Android TV
box** via USB, with no extra hardware in the chain.

---

## Why Not Just Load EDSDK in the Android App Directly?

Canon ships an ARM64 Linux version of EDSDK (`libEDSDK.so`) starting with
v13.18.30 (July 2024). The architecture is right for an Android TV box — but
there is one hard blocker:

`libEDSDK.so` requires **GNU glibc** (`libc.so.6`). Android uses **Bionic
libc**, which is ABI-incompatible. Loading both in the same process causes
symbol conflicts (`malloc`, `pthread_create`, etc.) and TLS initialization
failures. This cannot be fixed with a version upgrade — it is a fundamental
incompatibility.

**CCAPI (Canon's Wi-Fi REST API) is the Wi-Fi path** — not chosen here because
the requirement is USB, not Wi-Fi.

---

## Solution: EDSDK Native Sidecar Process

The Android Linux kernel can execute a valid ARM32 or ARM64 ELF binary. If we
ship the matching glibc dynamic linker (`ld-linux-armhf.so.3` or
`ld-linux-aarch64.so.1`) alongside the binary and patch the ELF interpreter
path to point to it, the binary and all glibc dependencies run in complete
isolation from Android's Bionic — in their **own process**.

This is exactly how projects like Termux run Linux desktop programs on Android.
Canon's own readme already lists **Raspberry Pi 4 (ARM64)** and
**Jetson Nano (ARM64)** as target Linux environments for this SDK. The Android
TV box may be ARM64 **or** 32-bit userspace on ARMv8 silicon (`armeabi-v7a`
only — this Mini PC).

We write a small C++ HTTP server (`canon-sidecar`) using EDSDK, ship it inside
the APK (JNI `libcanon_sidecar.so` + glibc assets), and spawn it as a child
process. Flutter talks to `http://127.0.0.1:8791` by default.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Android TV Box                                              │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Flutter App (Pose / LocalCameraService)            │    │
│  │                                                     │    │
│  │  LocalCameraService                                 │    │
│  │  http://127.0.0.1:8791  ───────────────────────┐   │    │
│  └────────────────────────────────────────────────│───┘    │
│                                                   │         │
│  ┌────────────────────────────────────────────────▼───┐    │
│  │  CanonSidecarService  (Android foreground Service) │    │
│  │  Kotlin                                            │    │
│  │  · Extracts sidecar binary from APK assets         │    │
│  │  · Opens USB via UsbManager; JNI passes fd          │    │
│  │  · Launches canon-sidecar (ARM32 or ARM64)          │    │
│  │  · Restarts it if it crashes                       │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  canon-sidecar  (glibc Linux ELF, ARM32 or ARM64)  │    │
│  │  C++ · EDSDK · cpp-httplib                         │    │
│  │                                                     │    │
│  │  Bundled alongside binary (same directory):         │    │
│  │    libEDSDK.so       libusb-1.0.so.0               │    │
│  │    libstdc++.so.6    libgcc_s.so.1                  │    │
│  │    libc.so.6         libm.so.6                      │    │
│  │    libpthread.so.0   ld-linux-aarch64.so.1          │    │
│  │                                                     │    │
│  │  HTTP on 127.0.0.1:8791 — same API as Pi sidecar:  │    │
│  │    GET  /health                                     │    │
│  │    POST /camera/live-view                           │    │
│  │    POST /camera/preview?download=1  → JPEG          │    │
│  │    POST /camera/prepare-still                       │    │
│  │    POST /camera/capture?download=1  → JPEG          │    │
│  └────────────────────────┬───────────────────────────┘    │
│                            │ libusb / EDSDK                 │
└────────────────────────────│───────────────────────────────┘
                             │ USB cable (Micro-B)
                             ▼
                   Canon EOS 200D II
```

---

## What Gets Built

### 1. `canon_sidecar/` — C++ sidecar (this directory)

A small C++ program that:
- Initialises EDSDK and discovers the camera on USB
- Runs a lightweight HTTP server (using the header-only
  [cpp-httplib](https://github.com/yhirose/cpp-httplib) library)
- Serves the 5 endpoints the Flutter app already calls
- Runs EDSDK's event loop on a background thread; HTTP responses wait on it

| File | Purpose |
|---|---|
| `src/main.cpp` | HTTP server, endpoint routing, process entry point |
| `src/canon_camera.cpp` | EDSDK wrapper — session, live view, capture |
| `src/canon_camera.h` | EDSDK wrapper interface |
| `src/httplib.h` | cpp-httplib (header-only, vendored) |
| `src/usb_open_hook.c` | `LD_PRELOAD` hook: dup `CANON_USB_FD` on `__open_2` / `open` |
| `CMakeLists.txt` | Build definition (ARM32 + ARM64) |
| `Dockerfile` | Reproducible Ubuntu 20.04 cross-compile |
| `build.sh` | `SIDECAR_ARCHES=arm32` / `arm64` / both; copies into `jniLibs` + assets |

### 2. Android Kotlin + JNI spawn

| File | Change |
|---|---|
| `android/.../canon/CanonSidecarService.kt` | Foreground Service: extract assets, USB permission, spawn sidecar |
| `android/.../canon/CanonSidecarSpawner.kt` | JNI fork+exec with USB fd + `LD_PRELOAD` hook |
| `android/.../cpp/canon_sidecar_spawn.cpp` | Native spawn helper |
| `android/.../MainActivity.kt` | Starts `CanonSidecarService` on launch |

The binary is packaged as `jniLibs/<abi>/libcanon_sidecar.so` (so Android's
installer extracts it) plus glibc/libusb/hook under
`assets/canon_sidecar/<abi>/`.

### 3. Flutter / Dart

`CameraSidecarConfig` defaults to **on**:
`CAMERA_SIDECAR_ENABLED=true`, `CAMERA_SIDECAR_URL=http://127.0.0.1:8791`,
`CAMERA_SIDECAR_LIVE_PREVIEW=true`. Pose skips CameraX when sidecar live
preview is active (Mini PCs with zero Camera2 cameras). Capture may substitute
the last EVF JPEG when the shutter still is far darker than live view.

Debug run (from `photobooth/`):

```bash
flutter run --debug --no-enable-impeller
```

C++ / JNI changes need `SIDECAR_ARCHES=arm32 ./build.sh` then a **full**
`flutter run`. Dart-only: hot restart (`R`). See [`SETUP.md`](SETUP.md).

---

## How the glibc Problem Is Solved

`libEDSDK.so` depends on `libc.so.6` (glibc), which Android does not provide.
The solution:

1. **Bundle glibc**: Copy `libc.so.6`, `libm.so.6`, `libpthread.so.0`,
   `ld-linux-aarch64.so.1`, and the C++ runtime libraries from the Ubuntu 20.04
   ARM64 package manager into the `bundle/` directory alongside the binary.

2. **Patch the ELF interpreter**: Use `patchelf` to change the binary's
   embedded interpreter path from the system path
   (`/lib/ld-linux-aarch64.so.1`) to a relative `$ORIGIN` path so it finds the
   bundled interpreter:
   ```
   patchelf --set-interpreter '$ORIGIN/ld-linux-aarch64.so.1' canon-sidecar
   patchelf --set-rpath '$ORIGIN' canon-sidecar
   ```

3. **Result**: The sidecar process loads its own private copy of glibc. Android's
   Bionic is not involved in the sidecar process at all. No symbol conflicts.

---

## Build Instructions

### Prerequisites

- Docker Desktop (any host OS: macOS, Windows, Linux)
- The Canon EDSDK v13.20.21 directory at
  `/Users/janakiram/Downloads/EDSDK132021CD(13.20.21)` (or set `EDSDK_PATH`
  in `build.sh`)

### One-command build

```bash
cd canon_sidecar
./build.sh                 # ARM32 + ARM64
# SIDECAR_ARCHES=arm32 ./build.sh   # this Mini PC (32-bit userspace)
```

This:
1. Builds a Docker image with the Ubuntu 20.04 ARM32/ARM64 cross-compile toolchain
2. Compiles `canon-sidecar` for Linux ARM32 and/or ARM64 inside the container
3. Copies glibc + libusb + C++ runtime `.so` files and runs `patchelf`
4. Copies JNI + assets into
   `photobooth/android/app/src/main/jniLibs/<abi>/` and
   `photobooth/android/app/src/main/assets/canon_sidecar/<abi>/`

### After build

Debug (preferred):

```bash
cd ../photobooth
flutter run --debug --no-enable-impeller
```

Release APK (version-sync wrapper; dart-defines optional — defaults are on):

```bash
cd ../photobooth
./scripts/flutter_with_version.sh build apk --release
```

---

## EDSDK Operations Used

| HTTP endpoint | EDSDK calls |
|---|---|
| `GET /health` | `EdsGetCameraList` + `EdsGetChildCount` → connected flag |
| `POST /camera/live-view` | `EdsSetPropertyData(kEdsPropID_Evf_Mode, 1)` + `EdsSetPropertyData(kEdsPropID_Evf_OutputDevice, kEdsEvfOutputDevice_PC)` |
| `POST /camera/preview?download=1` | `EdsCreateMemoryStream` + `EdsCreateEvfImageRef` + `EdsDownloadEvfImage` → JPEG bytes |
| `POST /camera/prepare-still` | Stop EVF output; set `_stillArmed` so preview polling does not re-arm EVF |
| `POST /camera/capture?download=1` | JPEG-only (`EdsImageQuality_LJF`); AF Halfway then Completely, NonAF fallback; wait for JPEG SOI; resume live view |

---

## USB Permission Flow on Android

Android requires explicit user permission before an app can communicate with a
USB device. The flow:

1. Camera is connected to the Android box via USB cable.
2. Android fires `USB_DEVICE_ATTACHED` intent → `MainActivity` receives it
   (already declared in `AndroidManifest.xml`).
3. `CanonUsbPermissionManager` checks if permission is already granted
   (`UsbManager.hasPermission(device)`).
4. If not granted, a system dialog appears asking the user to allow access.
   On a managed kiosk device (MDM / device-owner), this dialog can be
   suppressed.
5. Once permission is granted, Kotlin opens the device with
   `UsbManager.openDevice()`. JNI fork+exec inherits that fd.
   `LD_PRELOAD` `libusb_open_hook.so` intercepts **`__open_2`** (Ubuntu
   libusb is built with `_FORTIFY_SOURCE`) and `dup()`s the permitted fd
   when EDSDK opens `CANON_USB_PATH`. Hooking `open()` alone is not enough.

**Reboot behaviour**: USB permission grants survive reboots on most Android TV
boxes when the `android.hardware.usb.action.USB_DEVICE_ATTACHED` intent filter
is declared in the manifest with a `<meta-data>` device filter. The system
re-triggers the intent on attach and re-grants permission automatically for
known (previously approved) devices.

---

## 4-Shot Burst

No changes required to the burst logic. Each of the 4 shots continues to call
`POST /camera/capture?download=1` independently, exactly as the Pi sidecar did.
The sidecar re-arms live view after each capture before returning the HTTP
response (mirrors the existing `resumeLiveView=1` query param behaviour).
The existing loop in `photo_capture_flashback_auto_helpers.dart` and the
`UvcCaptureConfig.keepControllerOpenForClassicFourShot` flag both work unchanged.

---

## Known Constraints

| Constraint | Detail |
|---|---|
| **EDSDK commercial license** | Canon requires a signed agreement for commercial/event products using EDSDK. Apply before shipping. |
| **glibc version** | Built against Ubuntu 20.04 glibc 2.31. Works on Android boxes with kernel 4.14+. Avoid building on Ubuntu 22.04+ (glibc 2.35 may use syscalls not available on older kernels). |
| **SELinux** | Most Android TV boxes run SELinux in permissive mode or allow exec from `/data/data`. If enforcing mode blocks exec, set the sidecar data directory context with `restorecon` or use an MDM policy. |
| **USB cable** | EOS 200D II uses Micro-USB (not USB-C). Use Canon's OEM cable. Keep cable short and routed away from guests. |
| **Camera power** | Live view drains LP-E17 battery in ~90 min. Use Canon ACK-E17 AC adapter kit for kiosk use. |
| **Auto power-off** | Must be disabled on the camera: Settings → Auto power off → Disable. |
| **Single camera** | This implementation manages one camera. Multi-camera support is possible (EDSDK supports it) but out of scope. |

---

## Validation Checklist (before Android box deployment)

- [ ] Build `MultiCamCui` sample from EDSDK on a Raspberry Pi 4 (64-bit OS)
      and verify live view + capture work with the EOS 200D II over USB
- [ ] Build `canon-sidecar` on the same Pi; confirm same results via `curl`
- [ ] Run `patchelf` + bundle; copy to Pi; confirm binary still runs
- [ ] Install APK on Android box; confirm sidecar starts and `/health` responds
- [ ] Verify live preview in the Flutter pose screen
- [ ] Run a full 4-shot Classic session end-to-end
- [ ] Confirm USB permission dialog does not reappear after reboot

---

## Directory Structure (after build)

```
canon_sidecar/
├── README.md
├── SETUP.md
├── CMakeLists.txt
├── Dockerfile
├── build.sh
└── src/
    ├── main.cpp
    ├── canon_camera.cpp
    ├── canon_camera.h
    ├── usb_open_hook.c
    └── httplib.h
```

```
photobooth/android/app/src/main/
├── assets/canon_sidecar/<abi>/   ← glibc, libusb, usb_open_hook
├── jniLibs/<abi>/                ← libcanon_sidecar.so, libEDSDK.so, ld-linux
├── cpp/                          ← JNI spawn
├── kotlin/.../canon/             ← CanonSidecarService, USB, ABI
└── res/xml/device_filter.xml
```
