# Camera Selection Flow Documentation

## How Cameras Are Passed Between Screens

### Current Implementation

Cameras are **NOT passed as parameters** between screens. Instead, they are shared via a **shared state management system** using Provider.

### Architecture

1. **Shared State**: `CameraViewModel` is provided at the app level via `ChangeNotifierProvider` in `main.dart`
2. **Camera Selection Screen**: Reads and updates `CameraViewModel.selectedCamera`
3. **Photo Capture Screen**: Reads `CameraViewModel.selectedCamera` to get the selected camera

### Camera Identification

Cameras are identified using **unique identifiers**:

1. **Primary Identifier**: `camera.name` (iOS camera device identifier)
   - Format: `"com.apple.avfoundation.avcapturedevice.built-in_video:8"`
   - This is the **most reliable** identifier as it's unique per camera device
   - Example values:
     - Built-in back camera: `"com.apple.avfoundation.avcapturedevice.built-in_video:0"`
     - Built-in front camera: `"com.apple.avfoundation.avcapturedevice.built-in_video:1"`
     - External camera (HP 960K): `"com.apple.avfoundation.avcapturedevice.built-in_video:8"`

2. **Secondary Properties** (for verification):
   - `camera.lensDirection`: `CameraLensDirection.front`, `back`, or `external`
   - `camera.sensorOrientation`: Sensor orientation in degrees (typically 90)

### Data Flow

```
┌─────────────────────────┐
│  Camera Selection       │
│  Screen                 │
│                         │
│  1. Load cameras       │
│  2. User selects camera │
│  3. Store in            │
│     CameraViewModel     │
└───────────┬─────────────┘
            │
            │ (Shared Provider)
            │
            ▼
┌─────────────────────────┐
│  CameraViewModel        │
│  (Provider)             │
│                         │
│  - availableCameras     │
│  - selectedCamera       │
│    (CameraInfoModel)    │
└───────────┬─────────────┘
            │
            │ (Read selectedCamera)
            │
            ▼
┌─────────────────────────┐
│  Photo Capture          │
│  Screen                 │
│                         │
│  1. Read selectedCamera│
│  2. Match by uniqueId   │
│  3. Initialize camera   │
└─────────────────────────┘
```

### Camera Matching Logic

When cameras are loaded or when navigating between screens:

1. **Selection Storage**: The selected camera is stored as a `CameraInfoModel` object with:
   - `camera`: The `CameraDescription` object
   - `name`: Display name (e.g., "HP 960 4K Camera")
   - `uniqueId`: The camera's unique identifier (`camera.name`)

2. **Matching Process**:
   ```dart
   // When restoring selection after reload
   final matchingCamera = availableCameras.firstWhere(
     (camera) => camera.uniqueId == previouslySelectedCameraId,
   );
   ```

3. **Verification**: Before initializing, the app verifies:
   - The selected camera exists in the available cameras list
   - The unique ID matches exactly
   - The camera description properties match

### Key Code Locations

1. **Camera Selection**:
   - `lib/screens/camera_selection/camera_selection_viewmodel.dart`
   - `selectCamera()` method stores the selected camera

2. **Camera Retrieval**:
   - `lib/screens/photo_capture/photo_capture_view.dart`
   - `_initializeCamera()` method reads the selected camera

3. **Camera Identification**:
   - `lib/screens/camera_selection/camera_info_model.dart`
   - `uniqueId` getter provides the camera identifier

### Debugging

The app includes comprehensive logging:

- `📷 Camera selected:` - When user selects a camera
- `🔄 Loading cameras...` - When cameras are being loaded
- `✅ Restored previously selected camera:` - When selection is restored
- `🔍 Looking for camera with ID:` - When searching for selected camera
- `✅ Found matching camera:` - When camera is found
- `❌ ERROR: Camera ID mismatch!` - When wrong camera is detected

### Potential Issues

1. **Camera Not Found**: If the selected camera is not in the available list:
   - The app falls back to the first available camera
   - A warning is logged

2. **Wrong Camera Initialized**: If iOS initializes a different camera:
   - The app detects the mismatch
   - An error is thrown with details

3. **Camera List Changes**: If cameras are reloaded:
   - The app tries to restore the previous selection by unique ID
   - If not found, it selects the first camera

### Best Practices

1. **Always use `uniqueId`** for camera matching (not object reference)
2. **Verify camera exists** before initializing
3. **Log camera operations** for debugging
4. **Handle camera not found** gracefully

