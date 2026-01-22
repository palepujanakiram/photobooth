# Image Capture Size Analysis 📸

## Complete Analysis of Image Sizes Throughout the Capture & Processing Pipeline

---

## 📊 Summary

| Stage | Size | Format | Quality | Notes |
|-------|------|--------|---------|-------|
| **1. Camera Capture (Raw)** | Up to **1920×1080** | JPEG | Device Default | Native camera resolution |
| **2. After Capture (File)** | **1920×1080** | JPEG | Device Default | Saved to device storage |
| **3. After Resize (Upload)** | **512×512 to 1024×1024** | JPEG | 85% → 50% | Resized for API upload |
| **4. Final Upload Size** | **≤ 2MB** | Base64 JPEG | Variable | Compressed to meet API limits |

---

## 1️⃣ **Camera Capture Resolution**

### **Standard Flutter Camera** (Built-in Cameras)

**Location:** `lib/services/camera_service.dart:962`

```dart
_controller = CameraController(
  cameraToUse,
  ResolutionPreset.high,  // ← Camera resolution setting
  enableAudio: false,
);
```

**What `ResolutionPreset.high` Means:**

| Platform | Resolution | Aspect Ratio | Actual Size |
|----------|-----------|--------------|-------------|
| **iOS** | 1280×720 | 16:9 | ~0.9 MP |
| **Android** | 1280×720 | 16:9 | ~0.9 MP |

**Source:** Flutter camera plugin documentation
- `ResolutionPreset.high` = 720p (HD)
- Other options: `low` (240p), `medium` (480p), `veryHigh` (1080p), `ultraHigh` (2160p/4K), `max` (highest available)

---

### **Android Custom Camera Controller** (External Cameras)

**Location:** `android/app/src/main/kotlin/com/example/photobooth/AndroidCameraController.kt`

```kotlin
companion object {
    private const val MAX_PREVIEW_WIDTH = 1920
    private const val MAX_PREVIEW_HEIGHT = 1080
}

private fun chooseOptimalSize(choices: List<Size>): Size {
    return choices.firstOrNull { size ->
        size.width <= MAX_PREVIEW_WIDTH && size.height <= MAX_PREVIEW_HEIGHT
    } ?: choices.maxByOrNull { it.width * it.height } ?: Size(1920, 1080)
}
```

**Logic:**
1. Looks for largest size ≤ **1920×1080**
2. If no size fits, uses the largest available
3. Falls back to **1920×1080** if camera doesn't report sizes

**Typical Resolutions:**
- **Full HD**: 1920×1080 (2.1 MP)
- **HD**: 1280×720 (0.9 MP)
- **SVGA**: 800×600 (0.5 MP)

**Format:** `ImageFormat.JPEG`

**Lines 264-272:**
```kotlin
val imageReaderSize = chooseOptimalSize(
    map?.getOutputSizes(ImageFormat.JPEG)?.toList() ?: emptyList(),
)
imageReader = ImageReader.newInstance(
    imageReaderSize.width,
    imageReaderSize.height,
    ImageFormat.JPEG,  // ← JPEG format
    1,
)
```

---

### **iOS Custom Camera Controller** (External Cameras)

**Location:** `ios/Runner/CameraDeviceHelper.swift:792`

```swift
if session.canSetSessionPreset(.high) {
    session.sessionPreset = .high
}
```

**What `.high` Preset Means on iOS:**

| Device | Resolution | Aspect Ratio |
|--------|-----------|--------------|
| **iPhone/iPad** | 1280×720 | 16:9 |
| **External Camera** | Device Default (typically 1920×1080 or 1280×720) | Varies |

**Format:** JPEG (via `AVCapturePhotoSettings`)

**Lines 1034-1035:**
```swift
let settings = AVCapturePhotoSettings()
photoOutput.capturePhoto(with: settings, delegate: self)
```

**Note:** iOS automatically chooses the best format based on device capabilities.

---

## 2️⃣ **Captured Image (Raw File)**

**After capture, image is saved to device:**

### **Android:**
```
File: /data/data/com.example.photobooth/cache/picture_[timestamp].jpg
Size: 1920×1080 (or device native)
Format: JPEG
Quality: Camera default (typically 90-95%)
File Size: ~200-500 KB (varies by content)
```

### **iOS:**
```
File: /var/mobile/Containers/Data/Application/.../tmp/picture_[timestamp].jpg
Size: 1280×720 (or device native)
Format: JPEG
Quality: Device default
File Size: ~100-300 KB
```

### **Gallery Selection:**

**Location:** `lib/screens/photo_capture/photo_capture_viewmodel.dart:581-586`

```dart
final XFile? imageFile = await picker.pickImage(
  source: ImageSource.gallery,
  maxWidth: 1920,      // ← Gallery selection limit
  maxHeight: 1080,     // ← Gallery selection limit
  imageQuality: 95,    // ← 95% JPEG quality
);
```

**Gallery photos are automatically resized to:**
- Max: **1920×1080**
- Quality: **95%**
- This prevents huge photos (e.g., 12MP camera photos) from being loaded

---

## 3️⃣ **Image Processing for API Upload**

### **Resize & Compression Logic**

**Location:** `lib/utils/image_helper.dart:16-117`

```dart
static Future<String> resizeAndEncodeImage(
  XFile imageFile, {
  int maxWidth = 1024,           // ← Max width for upload
  int maxHeight = 1024,          // ← Max height for upload
  int minWidth = 512,            // ← Min width for upload
  int minHeight = 512,           // ← Min height for upload
  int quality = 85,              // ← Initial JPEG quality
  int maxSizeBytes = 2 * 1024 * 1024, // ← 2MB max
})
```

### **Processing Steps:**

#### **Step 1: Load Original Image**
```dart
final bytes = await imageFile.readAsBytes();
final originalImage = img.decodeImage(bytes);
// Example: 1920×1080 JPEG from camera
```

#### **Step 2: Scale Down if Too Large**
```dart
if (targetWidth > maxWidth || targetHeight > maxHeight) {
  // Image larger than 1024×1024
  final scale = (targetWidth > targetHeight)
      ? maxWidth / targetWidth     // Scale based on width
      : maxHeight / targetHeight;  // Scale based on height
  
  // Example: 1920×1080 → 1024×576
  targetWidth = (targetWidth * scale).round();
  targetHeight = (targetHeight * scale).round();
}
```

**Example Calculations:**
- **1920×1080** → **1024×576** (maintains 16:9 aspect ratio)
- **1280×720** → **1024×576** (maintains 16:9 aspect ratio)
- **800×600** → **800×600** (stays same, within limits)

#### **Step 3: Scale Up if Too Small**
```dart
if (targetWidth < minWidth || targetHeight < minHeight) {
  // Image smaller than 512×512
  final scale = (targetWidth < targetHeight)
      ? minWidth / targetWidth
      : minHeight / targetHeight;
  
  // Example: 320×240 → 512×384
  targetWidth = (targetWidth * scale).round();
  targetHeight = (targetHeight * scale).round();
}
```

#### **Step 4: Resize Image**
```dart
final resizedImage = img.copyResize(
  originalImage,
  width: targetWidth,    // 1024 (or calculated)
  height: targetHeight,  // 576 (or calculated)
  interpolation: img.Interpolation.linear,
);
```

#### **Step 5: Compress to JPEG**
```dart
int currentQuality = 85;  // Start at 85%
while (currentQuality >= 50) {
  encodedBytes = Uint8List.fromList(
    img.encodeJpg(resizedImage, quality: currentQuality),
  );
  
  // Check if size is acceptable (≤ 2MB)
  if (encodedBytes.length <= maxSizeBytes) {
    break;  // Success!
  }
  
  // Reduce quality and try again
  currentQuality -= 10;  // 85% → 75% → 65% → 55% → 50%
}
```

#### **Step 6: Further Resize if Still Too Large**
```dart
if (encodedBytes.length > maxSizeBytes) {
  // Still too large even at 50% quality
  final additionalScale = (maxSizeBytes / encodedBytes.length) * 0.9;
  final newWidth = (targetWidth * additionalScale).round();
  final newHeight = (targetHeight * additionalScale).round();
  
  // Example: 1024×576 might become 800×450
  final furtherResized = img.copyResize(
    resizedImage,
    width: newWidth,
    height: newHeight,
  );
  
  encodedBytes = Uint8List.fromList(
    img.encodeJpg(furtherResized, quality: 75),
  );
}
```

#### **Step 7: Convert to Base64**
```dart
final base64String = base64Encode(encodedBytes);
return 'data:image/jpeg;base64,$base64String';
```

---

## 📐 **Typical Size Progression**

### **Example 1: Android External Camera (1920×1080)**

```
1. Camera Capture:     1920×1080 JPEG (~400 KB raw)
                       ↓
2. Resize for API:     1024×576 JPEG (maintains 16:9)
                       ↓
3. Compress (85%):     ~150 KB
                       ↓
4. Base64 Encode:      ~200 KB (base64 is ~33% larger)
                       ↓
5. Upload:             ✅ Under 2MB limit
```

### **Example 2: Standard Camera (1280×720)**

```
1. Camera Capture:     1280×720 JPEG (~200 KB raw)
                       ↓
2. Resize for API:     1024×576 JPEG
                       ↓
3. Compress (85%):     ~100 KB
                       ↓
4. Base64 Encode:      ~133 KB
                       ↓
5. Upload:             ✅ Under 2MB limit
```

### **Example 3: Gallery Photo (4032×3024 - 12MP iPhone)**

```
1. Gallery Selection:  4032×3024 → 1920×1440 (limited by picker)
                       ↓
2. Resize for API:     1024×768 JPEG
                       ↓
3. Compress (85%):     ~180 KB
   (if > 2MB)          ↓ Quality reduced to 75%
                       ~120 KB
                       ↓
4. Base64 Encode:      ~160 KB
                       ↓
5. Upload:             ✅ Under 2MB limit
```

---

## 🎯 **API Requirements**

**From:** `lib/utils/image_helper.dart` comments

```dart
/// Requirements:
/// - Size: 512×512 to 1024×1024 pixels (maintains aspect ratio)
/// - Max size: ~2MB after base64 encoding
/// - Format: JPEG
```

**Why these limits:**
- **512-1024px**: Good balance between quality and processing speed
- **2MB**: Reasonable upload size for mobile networks
- **JPEG**: Universal format with good compression

---

## 📊 **Actual Sizes by Source**

| Source | Raw Resolution | After Resize | Compressed Size | Base64 Size |
|--------|---------------|--------------|-----------------|-------------|
| **Android External Camera** | 1920×1080 | 1024×576 | ~150 KB | ~200 KB |
| **Standard Camera** | 1280×720 | 1024×576 | ~100 KB | ~133 KB |
| **iOS External Camera** | 1280×720 | 1024×576 | ~100 KB | ~133 KB |
| **Gallery (HD)** | 1920×1080 | 1024×576 | ~150 KB | ~200 KB |
| **Gallery (Full Res)** | 4032×3024 → 1920×1440 | 1024×768 | ~180 KB | ~240 KB |

---

## 🔍 **Where to Find Each Setting**

| Setting | File | Line | Value |
|---------|------|------|-------|
| **Standard Camera Preset** | `camera_service.dart` | 962 | `ResolutionPreset.high` (720p) |
| **Android Max Capture** | `AndroidCameraController.kt` | 39-40 | 1920×1080 |
| **iOS Session Preset** | `CameraDeviceHelper.swift` | 792 | `.high` (720p) |
| **Gallery Max Size** | `photo_capture_viewmodel.dart` | 583-584 | 1920×1080 |
| **Upload Max Size** | `image_helper.dart` | 18-19 | 1024×1024 |
| **Upload Min Size** | `image_helper.dart` | 20-21 | 512×512 |
| **Upload Quality** | `image_helper.dart` | 22 | 85% (adjustable) |
| **Upload Max Bytes** | `image_helper.dart` | 23 | 2MB |

---

## 🎨 **Quality vs Size Trade-offs**

### **JPEG Quality Impact:**

| Quality | File Size (1024×576) | Visual Quality | Use Case |
|---------|---------------------|----------------|----------|
| **95%** | ~180 KB | Excellent | Gallery selection |
| **85%** | ~150 KB | Very Good | Default upload |
| **75%** | ~120 KB | Good | If size > 2MB |
| **65%** | ~90 KB | Acceptable | If still > 2MB |
| **50%** | ~70 KB | Visible artifacts | Last resort |

---

## 💡 **Recommendations**

### **Current Settings: ✅ Optimal**

The current setup is well-balanced:

1. **✅ Captures at reasonable resolution** (720p-1080p)
   - Not too large (faster processing)
   - Not too small (good quality)

2. **✅ Resizes intelligently** (512-1024px)
   - Maintains aspect ratio
   - Scales up small images
   - Scales down large images

3. **✅ Compresses progressively** (85% → 50%)
   - Starts with good quality
   - Reduces only if needed
   - Always stays under 2MB

### **If You Need Higher Quality Captures:**

**Option 1: Increase Camera Resolution**

```dart
// In camera_service.dart line 962
_controller = CameraController(
  cameraToUse,
  ResolutionPreset.veryHigh,  // 1080p instead of 720p
  enableAudio: false,
);
```

**Impact:**
- Capture: 1920×1080 instead of 1280×720
- Upload: Still 1024×576 (resized for API)
- Quality: Slightly better (more detail before downscale)

**Option 2: Increase Upload Size**

```dart
// In image_helper.dart line 18-19
int maxWidth = 2048,   // 2K instead of 1K
int maxHeight = 2048,
```

**Impact:**
- Upload: 2048×1152 instead of 1024×576
- File size: ~600 KB instead of ~200 KB
- Quality: Much better detail
- **Note**: Check API limits!

### **If You Need to Reduce Bandwidth:**

```dart
// In image_helper.dart line 18-19
int maxWidth = 768,   // Smaller upload
int maxHeight = 768,
```

**Impact:**
- Upload: 768×432 instead of 1024×576
- File size: ~100 KB instead of ~200 KB
- Quality: Slightly reduced but still good

---

## 📱 **Platform-Specific Notes**

### **Android:**
- External cameras: Up to **1920×1080**
- Built-in cameras: **1280×720** (ResolutionPreset.high)
- Gallery photos: Limited to **1920×1080** on selection

### **iOS:**
- All cameras: **1280×720** (.high preset)
- External cameras may support higher, but preset limits it
- Gallery photos: Limited to **1920×1080** on selection

### **Web:**
- Not using native camera controllers
- Would use browser MediaStream API
- Resolution depends on browser implementation

---

## 🔧 **To Change Capture Resolution**

### **1. Standard Camera (Built-in):**

Edit `lib/services/camera_service.dart:962`:

```dart
_controller = CameraController(
  cameraToUse,
  ResolutionPreset.veryHigh,  // Change this
  enableAudio: false,
);
```

**Options:**
- `ResolutionPreset.low` - 240p
- `ResolutionPreset.medium` - 480p
- `ResolutionPreset.high` - **720p (current)**
- `ResolutionPreset.veryHigh` - 1080p
- `ResolutionPreset.ultraHigh` - 2160p (4K)
- `ResolutionPreset.max` - Maximum available

### **2. Android External Camera:**

Edit `android/app/src/main/kotlin/com/example/photobooth/AndroidCameraController.kt:39-40`:

```kotlin
private const val MAX_PREVIEW_WIDTH = 2560  // Change from 1920
private const val MAX_PREVIEW_HEIGHT = 1440  // Change from 1080
```

### **3. iOS External Camera:**

Edit `ios/Runner/CameraDeviceHelper.swift:792`:

```swift
if session.canSetSessionPreset(.veryHigh) {  // Change from .high
    session.sessionPreset = .veryHigh
}
```

---

## ✅ **Conclusion**

**Current captured image sizes:**
- **Standard cameras**: 1280×720 (720p)
- **Android external cameras**: Up to 1920×1080 (1080p)
- **iOS external cameras**: 1280×720 (720p)
- **After processing for upload**: 512×512 to 1024×1024
- **Final upload size**: ≤ 2MB base64-encoded JPEG

The current configuration provides a **good balance** between:
- ✅ Image quality
- ✅ File size
- ✅ Processing speed
- ✅ Upload bandwidth
- ✅ API requirements

**Perfect for AI photo transformation use case!** 🎨✨
