# Gallery Selection - Quick Start Guide

## 🎯 What Was Added?

A **gallery button** next to the camera capture button that allows users to select photos from their device when the camera isn't working.

## 📱 User Experience

### **On the Photo Capture Screen:**

```
┌─────────────────────────────┐
│      Camera Preview         │
└─────────────────────────────┘

      🖼️        📷
    Gallery   Capture
```

**Two options:**
1. **📷 Capture** - Take photo with camera (main button, larger)
2. **🖼️ Gallery** - Select from photos (smaller button, left side)

## 🚀 How It Works

### **Camera Issues? Use Gallery!**

```
❌ Camera not working
     ↓
👆 Tap gallery button
     ↓
📂 Select existing photo
     ↓
✅ Continue with app
```

### **Complete Flow:**

1. User opens Photo Capture screen
2. Sees camera preview (or error if camera broken)
3. **Taps gallery button 🖼️**
4. Device gallery/photos app opens
5. User selects a photo
6. Photo loads into app
7. User taps "Continue"
8. Theme selection and AI transformation proceed normally

## 💡 When to Use Gallery?

| Scenario | Solution |
|----------|----------|
| 📷 Camera not working | Use gallery instead |
| ⏱️ Camera timeout | Select existing photo |
| 🔌 External camera issues | Bypass camera with gallery |
| 🧪 Testing/development | Faster than camera setup |
| 👤 User preference | Use existing good photo |

## 🛠️ Implementation Details

### **What Changed:**

**1. ViewModel (`photo_capture_viewmodel.dart`)**
```dart
// New method added
await viewModel.selectFromGallery();
```

**2. View (`photo_capture_view.dart`)**
```dart
// New gallery button added
CupertinoButton(
  onPressed: () => viewModel.selectFromGallery(),
  child: Icon(CupertinoIcons.photo),
)
```

### **Image Quality:**
- Max dimensions: **1920x1080** (same as camera)
- Quality: **95%** (high quality)
- Format: **JPEG**

### **Error Tracking:**
```dart
// Automatically tracked in Crashlytics
photo_source: 'gallery'  // vs 'camera'
```

## 🧪 Testing Checklist

- [ ] Build and run app
- [ ] Navigate to Photo Capture screen
- [ ] Tap gallery button
- [ ] Select a photo
- [ ] Verify photo shows in preview
- [ ] Tap "Continue"
- [ ] Verify theme selection works
- [ ] Complete full flow

### **Build Command:**
```bash
flutter clean
flutter pub get
flutter build apk --release
```

## 📊 What Gets Tracked?

In Firebase Crashlytics, you'll see:

```
Custom Keys:
  photo_source = 'gallery'  ← Shows gallery was used
  photo_id = 'uuid-123'
  session_id = 'session-xyz'

Breadcrumb Logs:
  📂 Gallery selection started
  ✅ Photo selected from gallery
```

This helps you understand:
- How many users use gallery vs camera
- If camera issues are forcing gallery use
- Success rate of photo selections

## ⚠️ Error Handling

### **User Cancels:**
- ✅ No error shown
- ✅ Returns to camera screen
- ✅ Can try again

### **Permission Denied:**
- ❌ Error message shown
- 📝 Logged to Crashlytics
- 🔄 User can grant permission and retry

### **Image Load Fails:**
- ❌ Error message: "Gallery Selection Failed"
- 📝 Full error logged
- 🔄 User can select different photo

## 🎨 Visual Design

**Gallery Button:**
- Size: 60x60px circle
- Icon: Photo/Gallery icon
- Position: Left side
- Style: Secondary button with border

**Capture Button:**
- Size: 80x80px circle
- Icon: Camera icon
- Position: Center
- Style: Primary button (main action)

## 🌟 Benefits

### **For Users:**
- ✅ Workaround for broken cameras
- ✅ Use existing photos
- ✅ Faster than fixing camera
- ✅ Works on all devices

### **For You:**
- ✅ Reduced camera issue complaints
- ✅ Better Android TV support
- ✅ Easier testing/debugging
- ✅ Analytics on camera vs gallery usage

## 📝 Summary

| Feature | Status |
|---------|--------|
| Gallery selection | ✅ Implemented |
| UI button | ✅ Added |
| Error handling | ✅ Complete |
| Error reporting | ✅ Integrated |
| Documentation | ✅ Created |
| Testing | ⏳ Ready for you |

## 🚀 Next Steps

1. **Build the app:**
   ```bash
   flutter build apk --release
   ```

2. **Deploy to Android TV**

3. **Test the gallery button:**
   - Tap gallery icon
   - Select photo
   - Continue with flow

4. **Check Crashlytics:**
   - Monitor `photo_source` key
   - Track gallery usage
   - Monitor for errors

5. **Share with your team** to test on remote Android TV

---

**Result**: Users can now complete the photo booth experience even when the camera is broken! 🎉

**Alternative Flow**: Camera not working? → Use Gallery → Success! ✅
