# Camera List, Default Selection, and Preview Flow

This document describes how the Photo Booth app fetches the list of available cameras, selects a default camera, and displays the live preview of the selected camera.

---

## 1. Entry point: Opening the Capture screen

**Where:** `lib/screens/photo_capture/photo_capture_view.dart`

When the user navigates to the **Capture Photo** screen:

1. `PhotoCaptureScreen` is built and `initState()` runs.
2. A **post-frame callback** is registered so that after the first frame:
   - `loadPreviewRotation()` loads the saved preview rotation (e.g. 90° for external cameras).
   - `_resetAndInitializeCameras()` is called.

So the flow starts with **reset and initialize cameras**, which drives both camera list loading and default selection.

---

## 2. Resetting and initializing cameras

**Where:** `lib/screens/photo_capture/photo_capture_viewmodel.dart` → `resetAndInitializeCameras()`

High-level steps:

1. **Dispose any existing camera**
   - If a standard `CameraController` exists, it is disposed.
   - If the app is using a custom controller (external camera), it is disposed via `_cameraService.dispose()`.
   - A short delay (100 ms) is applied only when something was actually disposed, so the system can release the previous camera.

2. **Clear state**
   - `_currentCamera = null`, `_errorMessage = null`.

3. **Load cameras**
   - `await loadCameras()` (see §3).

4. **Default selection**
   - If the list is not empty, `_currentCamera = _pickDefaultCamera(_availableCameras)` (see §4).

5. **Initialize the selected camera**
   - `await initializeCamera(_currentCamera!)` (see §5).

The whole block is wrapped in a **25-second timeout**; on timeout the user sees an error and can retry.

---

## 3. Fetching the camera list

### 3.1 View model: `loadCameras()`

**Where:** `lib/screens/photo_capture/photo_capture_viewmodel.dart` → `loadCameras()`

1. Sets `_isLoadingCameras = true` and notifies listeners (UI can show loading).
2. Calls **`_cameraService.getAvailableCameras()`** to get the raw list.
3. **Filters** the list with `_filterCamerasByDeviceType()`:
   - On **tablet/TV** (or when `_deviceType` says so): only cameras that are external (by `lensDirection` or by name heuristics).
   - On **phone**: only built-in (non-external) cameras.
   - If the filtered list is empty, the full list is used so the user always has at least one camera.
4. **Sorts** with `_externalCamerasFirst()` so external cameras appear first.
5. Stores the result in **`_availableCameras`** and notifies listeners.

So the “list” the rest of the flow uses is **filtered and sorted**, not the raw list.

### 3.2 Camera service: `getAvailableCameras()`

**Where:** `lib/services/camera_service.dart` → `getAvailableCameras()`

This returns a list of `CameraDescription` that the view model will filter and sort.

**iOS**

- Ensures the camera change listener is set up (if needed).
- Calls the Flutter `camera` plugin’s **`availableCameras()`** and uses that as the list.

**Android**

- Two sources are used and then merged:
  1. **Flutter `camera` plugin:** `availableCameras()` (standard Flutter camera list).
  2. **Native Camera2 + USB:** `AndroidCameraDeviceHelper.getAllAvailableCameras()` (method channel to Android).
- These two calls are run **in parallel** with `Future.wait([...])` to reduce time to first preview.
- The Flutter list is the base; the native list is used to **merge and enrich**:
  - Match native entries to Flutter cameras by ID (e.g. `"0"`, `"1"` vs `"Camera 0"`, `"Camera 1"`).
  - Mark external cameras (e.g. by `LENS_FACING_EXTERNAL`, USB source, or name).
  - Add cameras that appear only in the native list (e.g. USB cameras on Android TV that are not yet in Flutter’s list).
  - Store USB vendor/product IDs for later resolution of `usb_*` IDs to Camera2 IDs.
  - Optionally replace generic “External Camera” with the real USB product name.

So on Android, the final list is a **merge of Flutter’s list and the native Camera2/USB list**, with external vs built-in and naming corrected.

### 3.3 Android native: `getAllAvailableCameras()`

**Where:** `android/.../CameraDeviceHelper.kt` → `getAllAvailableCameras(result)`

- **Camera2 list:** `getCamera2Cameras()`:
  - Gets `cameraIdList` from `CameraManager`.
  - For each ID, reads characteristics and builds a map: `uniqueID`, `localizedName`, `source: "camera2"`.
  - Names are derived from `LENS_FACING` (e.g. Back/Front/External) or from camera index (e.g. “External USB Camera” for high IDs).
- **USB list:** `getUsbCameras(camera2Cameras)`:
  - Uses `UsbManager` to enumerate UVC devices.
  - Adds cameras that are not already in the Camera2 list (by Camera2 ID), so USB cams that are not yet in `cameraIdList` (e.g. on some Android TVs) still appear.
- **Names:** `applyUsbProductNamesToCameraList()` can replace “External Camera” with the actual USB product name when a match is found.
- The combined list is returned to Flutter via **`result.success(cameras)`**.

So the “camera list” on Android is **Camera2 IDs plus USB-only devices**, with stable IDs and human-readable names.

---

## 4. Default camera selection

**Where:** `lib/screens/photo_capture/photo_capture_viewmodel.dart` → `_pickDefaultCamera(List<CameraDescription> cameras)`

Selection order:

1. **By name (external-looking names)**
   - Any camera for which `_looksLikeExternalCameraName(c.name)` is true (e.g. long UUID-style names on iOS, or names containing “webcam”, “usb”, “external” and not “built-in”).
   - If at least one exists, **the first such camera** is returned.

2. **By direction**
   - Any camera with `lensDirection == CameraLensDirection.external`.
   - If at least one exists, **the first such camera** is returned.

3. **Fallback**
   - **`cameras.first`** (first in the list; the list is already sorted with external first).

So the default is **“first external-looking or external camera, otherwise first in list”**.

`_looksLikeExternalCameraName()` treats as external: long names with hyphens (e.g. iOS UUID), or lowercase name containing “webcam”, “usb”, “external”, and excludes names containing “built-in”.

---

## 5. Initializing the selected camera

**Where:**  
- View model: `lib/screens/photo_capture/photo_capture_viewmodel.dart` → `initializeCamera(CameraDescription camera)`  
- Service: `lib/services/camera_service.dart` → `initializeCamera(CameraDescription camera)`  
- Android: `MainActivity` + `AndroidCameraController`

### 5.1 View model: `initializeCamera(camera)`

1. **Dispose previous**
   - If there is an existing `_cameraController` or custom controller, dispose it and call `_cameraService.dispose()`.
   - If anything was disposed, wait 100 ms.
2. **Delegate to service**
   - `await _cameraService.initializeCamera(camera)`.
3. **If using custom controller (external camera)**
   - **SurfaceView path:** `customController.startPreview()` is fired without awaiting (preview will actually start when the SurfaceView surface is ready). Errors (except CANCELLED) are caught and shown.
   - **Texture path:** `await customController.startPreview()` then a short delay, then set `_currentCamera`, clear `_isInitializing`, and notify.
4. **If using standard controller**
   - Standard `CameraController` is created and initialized; preview is started via the plugin.
5. **State**
   - `_currentCamera = camera`, `_isInitializing = false`, `_errorMessage = null`, `notifyListeners()`.

So the view model decides **who** owns the camera (service + custom vs standard) and **when** to consider initialization “done” and show the preview UI.

### 5.2 Camera service: `initializeCamera(camera)`

**Where:** `lib/services/camera_service.dart` → `initializeCamera(CameraDescription camera)`

- Disposes any existing `_controller` and `_customController`.
- Decides **controller type**:
  - **External (by direction or by name on iOS):** use **custom controller** (native Camera2 on Android, native AVFoundation on iOS).
  - **Otherwise:** use Flutter `camera` plugin’s **standard** `CameraController`.

**Android external camera (custom controller):**

- Resolves **device ID** from `camera.name` (e.g. `"Camera 5"` → `"5"`, or keep as-is if already numeric).
- If the name is a USB-only ID (`usb_*`), it is resolved to a Camera2 ID (in-memory or via `AndroidCameraDeviceHelper.resolveUsbToCamera2Id(...)`).
- Creates `CustomCameraController` and calls **`initialize(deviceIdToUse, useSurfaceView: kUseSurfaceViewForPreview, rotation: kCameraPreviewRotationDefault)`**.
- `kUseSurfaceViewForPreview` is currently **false**, so the **Texture** path is used (SurfaceTexture + supported buffer size).

**Custom controller `initialize()` (platform channel):**

- Invokes method **`initializeCamera`** with `deviceId`, and optionally `useSurfaceView` and `rotation`.
- **MainActivity** handles it:
  - **SurfaceView:** `initializeCameraWithSurfaceView(deviceId, rotation, result)` → reuses or creates `AndroidCameraController` and calls **`prepareForSurfaceView(deviceId, rotation, result)`** (camera is opened when the surface is ready).
  - **Texture:** `initializeCamera(deviceId, result)` → creates `AndroidCameraController` with `TextureRegistry`, then **`controller.initialize(deviceId, result)`** which creates a SurfaceTexture, sets a **supported** preview buffer size, opens the camera, and creates the capture session.

So on Android, **Texture path** = one-shot init with SurfaceTexture and supported size; **SurfaceView path** = prepare first, open camera only after the SurfaceView reports a valid surface.

### 5.3 Android: Opening camera and creating the session

**Where:** `android/.../AndroidCameraController.kt`

**Texture path:**

- `initialize(cameraId, result)`:
  - Gets characteristics, starts background thread, creates **SurfaceTexture** (via Flutter’s texture registry), calls **`setupPreviewSurface`** (chooses a supported size and **`setDefaultBufferSize(width, height)`**), **`setupImageReader`** for JPEG capture.
  - **`openCamera(cameraId, cameraStateCallback, backgroundHandler)`**.
- In **`onOpened`**: `cameraDevice = camera`; then **`createCaptureSession()`**.
- **`createCaptureSession()`**:
  - Uses the **Surface** from the SurfaceTexture (and the ImageReader surface).
  - Calls **`device.createCaptureSession(surfaces, captureStateCallback, backgroundHandler)`**.
- **`onConfigured`**: stores the session and, if there was a **pending preview result**, calls **`startPreviewInternal(result)`** and completes that result so Flutter’s `startPreview()` future completes.

**SurfaceView path (when enabled):**

- `prepareForSurfaceView(cameraId, rotation, result)` sets `useSurfaceView = true`, stores `currentCameraId`, sets up ImageReader, and completes the init result **without** opening the camera.
- When the platform view’s **Surface** is ready, **`onSurfaceReady(surface)`** is called → **`openCamera(currentCameraId!!, ...)`**.
- In **`onOpened`**: **`createCaptureSession()`** is called with **`externalPreviewSurface`** (the SurfaceView’s surface) and the ImageReader surface. Session configuration can fail on some devices if the SurfaceView size is not in the camera’s supported list; the app currently avoids this by using the Texture path by default.

**startPreview / startPreviewInternal:**

- Builds a **TEMPLATE_PREVIEW** request, adds the preview surface, and sets the repeating request so the camera streams frames to that surface. The Flutter side considers preview “running” when the `startPreview` platform call completes successfully.

---

## 6. Showing the preview in the UI

**Where:** `lib/screens/photo_capture/photo_capture_view.dart` (Builder under the capture screen’s content area)

The UI decides **what** to show based on controller type and readiness:

1. **Loading**
   - If `viewModel.isInitializing` or (no error and `availableCameras.isEmpty`): show a **loading indicator**.

2. **Error**
   - If `viewModel.hasError`: show error message and **Retry** button (calls `_resetAndInitializeCameras()`).

3. **Not ready**
   - If not using the SurfaceView placeholder and **not** `viewModel.isReady`: show “Camera not ready”.
   - **isReady** (view model): for custom controller, `customController?.isPreviewRunning ?? false`; for standard controller, controller exists and `value.isInitialized`.

4. **Preview widget**
   - **Custom controller + SurfaceView (Android):**  
     Build an **AndroidView** with view type `com.example.photobooth/camera_preview_surface`, creation params `rotation`. Layout uses a **rotation-based aspect ratio** (9:16 when rotation 90°/270°, else 16:9) and a minimum size so the surface is never zero-sized.

   - **Custom controller + Texture:**  
     Build a **Texture** widget with `textureId` from the custom controller. Same rotation-based aspect ratio and minimum size; **Transform.rotate** and **FittedBox** with **BoxFit.cover** for rotation and scaling.

   - **Standard controller:**  
     Use the plugin’s **CameraPreview** widget with `viewModel.cameraController!`.

   - **Else:**  
     Placeholder (“Camera preview not available”).

5. **Overlay**
   - For SurfaceView path, if not yet ready, a semi-transparent overlay with a spinner can be shown until the surface is ready and preview has started.

So the **selected camera** is the one stored in **`_currentCamera`** and used in **`initializeCamera`**; the **preview** is shown by the branch that matches the current controller type (SurfaceView vs Texture vs standard) and readiness.

---

## 7. Flow summary (sequence)

```
User opens Capture Photo screen
  → post-frame: loadPreviewRotation(); _resetAndInitializeCameras()
  → resetAndInitializeCameras()
       → dispose existing camera (if any)
       → loadCameras()
            → CameraService.getAvailableCameras()
                 → [Android] Future.wait([ availableCameras(), getAllAvailableCameras() ])
                 → [Android] Merge Flutter list + native Camera2/USB list; fix external/names
            → _filterCamerasByDeviceType(allCameras)  // tablet/TV → external only; phone → built-in
            → _externalCamerasFirst(...)
            → _availableCameras stored
       → _currentCamera = _pickDefaultCamera(_availableCameras)  // prefer external by name, then by direction, else first
       → initializeCamera(_currentCamera)
            → CameraService.initializeCamera(camera)
                 → [External] CustomCameraController.initialize(deviceId, useSurfaceView, rotation)
                      → Platform: initializeCamera / initializeCameraWithSurfaceView
                      → [Texture] Android: create SurfaceTexture, set supported buffer size, openCamera, createCaptureSession
            → startPreview() (Texture: await; SurfaceView: fire-and-forget)
            → _currentCamera set, _isInitializing = false, notifyListeners()
  → UI builds: isReady true → preview widget (Texture or SurfaceView or CameraPreview)
  → Native: onConfigured → startPreviewInternal → repeating request → frames to surface/texture
  → User sees live preview of the default (or selected) camera.
```

---

## 8. Key files reference

| Purpose | Flutter | Android |
|--------|---------|---------|
| Entry / reset | `photo_capture_view.dart` (initState, _resetAndInitializeCameras) | — |
| Load & filter list | `photo_capture_viewmodel.dart` (loadCameras, _filterCamerasByDeviceType, _externalCamerasFirst) | — |
| Get raw list | `camera_service.dart` (getAvailableCameras) | `CameraDeviceHelper.kt` (getAllAvailableCameras, getCamera2Cameras, getUsbCameras) |
| Default selection | `photo_capture_viewmodel.dart` (_pickDefaultCamera, _looksLikeExternalCameraName) | — |
| Init camera | `photo_capture_viewmodel.dart` (initializeCamera); `camera_service.dart` (initializeCamera) | `MainActivity.kt` (handleInitializeCamera); `AndroidCameraController.kt` (initialize, prepareForSurfaceView, onSurfaceReady, createCaptureSession, startPreviewInternal) |
| Preview UI | `photo_capture_view.dart` (Builder: Texture, AndroidView, CameraPreview) | `CameraPreviewSurfaceView.kt` (when SurfaceView path used) |

---

## 9. Constants

- **`kUseSurfaceViewForPreview`** (`lib/utils/constants.dart`): When `true`, Android external camera uses SurfaceView for preview; when `false`, uses Texture (supported buffer size, more reliable session configuration).
- **`kCameraPreviewRotationDefault`**: Default preview rotation in degrees (e.g. 90 for portrait on external cameras).
- **`kTabletBreakpoint`**: Shortest side >= this → tablet/TV; influences device type and thus camera filtering (external vs built-in).

This is the full flow from “open Capture screen” to “show live preview of the default or selected camera.”
