# Gallery Selection - UI Guide

## 📱 Visual Layout

### **Photo Capture Screen - Before**

```
┌─────────────────────────────────────┐
│                                     │
│       📷 Camera Preview             │
│                                     │
│                                     │
└─────────────────────────────────────┘

         ┌──────────┐
         │   📊     │
         │  Debug   │
         └──────────┘

              📷
         [Capture]
        (80x80px)


┌──────────────┬──────────────┐
│   [Front]    │    [Back]    │
└──────────────┴──────────────┘
```

### **Photo Capture Screen - After (NEW!)**

```
┌─────────────────────────────────────┐
│                                     │
│       📷 Camera Preview             │
│                                     │
│                                     │
└─────────────────────────────────────┘

         ┌──────────┐
         │   📊     │
         │  Debug   │
         └──────────┘

        🖼️       📷
     [Gallery] [Capture]
    (60x60px) (80x80px)
      NEW!


┌──────────────┬──────────────┐
│   [Front]    │    [Back]    │
└──────────────┴──────────────┘
```

## 🎨 Button Specifications

### **Gallery Button (NEW)**

```
┌─────────────────┐
│   🖼️           │
│                 │
│   Size: 60x60   │
│   Circle shape  │
│   Photo icon    │
│   Icon: 28px    │
│                 │
│   Border: 2px   │
│   Semi-trans    │
└─────────────────┘
```

**Properties:**
- **Size**: 60×60 pixels
- **Shape**: Perfect circle
- **Background**: Semi-transparent surface color (0.8 alpha)
- **Border**: 2px border with primary color (0.3 alpha)
- **Icon**: `CupertinoIcons.photo` at 28px
- **Position**: Left of capture button
- **Spacing**: 24px gap to capture button

### **Capture Button (Existing)**

```
┌─────────────────┐
│                 │
│      📷        │
│                 │
│   Size: 80x80   │
│   Circle shape  │
│   Camera icon   │
│   Icon: 40px    │
│                 │
│   Solid color   │
└─────────────────┘
```

**Properties:**
- **Size**: 80×80 pixels
- **Shape**: Perfect circle
- **Background**: Solid surface color
- **Icon**: `CupertinoIcons.camera` at 40px
- **Position**: Center/Right
- **Primary action**: Main button

## 🔄 States

### **1. Normal State**

```
Gallery Button      Capture Button
    🖼️                  📷
  (60x60)            (80x80)
  
  Active             Active
  Enabled            Enabled
```

### **2. Loading State**

```
Gallery Button      Capture Button
    ⏳                  ⏳
  (spinner)          (spinner)
  
  Loading...         Loading...
  Disabled           Disabled
```

### **3. Error State**

```
     ┌────────────────────┐
     │  ❌ Error Message  │
     │                    │
     │  [Dismiss Button]  │
     └────────────────────┘
     
Gallery Button      Capture Button
    🖼️                  📷
  
  Enabled            Enabled
  Ready to retry     Ready to retry
```

## 📐 Responsive Layout

### **Small Screens (Mobile)**

```
┌──────────────────┐
│   Camera View    │
└──────────────────┘

   🖼️     📷
Gallery Capture

[Camera Switches]
```

### **Large Screens (Tablet/TV)**

```
┌──────────────────────────────┐
│      Camera Preview          │
│         (Larger)             │
└──────────────────────────────┘

     🖼️        📷
  Gallery    Capture
  (Spaced further apart)

┌───────────────────────────────┐
│  [Front] [Back] [External]    │
└───────────────────────────────┘
```

## 🎯 User Interaction Flow

### **Gallery Selection Flow**

```
Step 1: User sees screen
┌─────────────────────┐
│  📷 Camera Preview  │
└─────────────────────┘
   🖼️       📷
    ↑
    User taps gallery

Step 2: Gallery opens
┌─────────────────────┐
│  📱 Device Gallery  │
│                     │
│  [Photo 1] [Photo 2]│
│  [Photo 3] [Photo 4]│
└─────────────────────┘
         ↓
    User selects photo

Step 3: Photo loaded
┌─────────────────────┐
│  ✅ Selected Photo  │
└─────────────────────┘
[Cancel]  [Continue] ←

Step 4: Continues with flow
```

### **Camera Capture Flow (Existing)**

```
Step 1: User sees screen
┌─────────────────────┐
│  📷 Camera Preview  │
└─────────────────────┘
   🖼️       📷
             ↑
        User taps camera

Step 2: Photo captured
┌─────────────────────┐
│  ✅ Captured Photo  │
└─────────────────────┘
[Cancel]  [Continue] ←

Step 3: Continues with flow
```

## 🎨 Color Scheme

### **Light Mode**

```
Gallery Button:
  Background: rgba(255, 255, 255, 0.8)
  Border: rgba(PRIMARY_COLOR, 0.3)
  Icon: Dark gray/black

Capture Button:
  Background: White/Light gray
  Icon: Dark gray/black
```

### **Dark Mode**

```
Gallery Button:
  Background: rgba(44, 44, 46, 0.8)
  Border: rgba(PRIMARY_COLOR, 0.3)
  Icon: White/Light gray

Capture Button:
  Background: Dark gray
  Icon: White/Light gray
```

## 📏 Spacing & Alignment

```
┌─────────────────────────────────┐
│                                 │
│          [Content]              │
│                                 │
└─────────────────────────────────┘

        ↕ 16px margin

     ┌──────────┐
     │  Debug   │
     └──────────┘

        ↕ 24px gap

    🖼️  ←24px→  📷  ←84px→ [space]
   60px        80px

        ↕ 16px gap

┌──────────────┬──────────────┐
│  [Camera 1]  │  [Camera 2]  │
└──────────────┴──────────────┘
```

## 🖱️ Interaction Design

### **Hover States (Web/Desktop)**

```
Gallery Button on hover:
┌─────────────┐
│   🖼️       │  ← Slight scale up (1.05x)
│   Opacity   │  ← Border becomes more visible
└─────────────┘
```

### **Press States**

```
Gallery Button pressed:
┌─────────────┐
│   🖼️       │  ← Scale down (0.95x)
│   Pressed   │  ← Background slightly darker
└─────────────┘
```

### **Disabled State**

```
Gallery Button disabled:
┌─────────────┐
│   🖼️       │  ← Opacity: 0.5
│   Disabled  │  ← No interaction
└─────────────┘
```

## 🎭 Animation

### **Button Press Animation**

```
1. User taps
   Scale: 1.0 → 0.95 (50ms)
   
2. Button pressed
   Scale: 0.95 (hold)
   
3. User releases
   Scale: 0.95 → 1.0 (150ms ease-out)
```

### **Loading Animation**

```
1. Button tapped
   Icon fades out (200ms)
   
2. Spinner fades in
   Rotation animation (continuous)
   
3. Action completes
   Spinner fades out (200ms)
   Icon fades in (200ms)
```

## 📱 Platform-Specific Behavior

### **iOS**

```
Gallery Button → Opens iOS Photos app
┌─────────────────────┐
│   📱 Photos         │
│                     │
│  Recent  Albums     │
│  [Grid of photos]   │
└─────────────────────┘
```

### **Android**

```
Gallery Button → Opens system picker
┌─────────────────────┐
│   Choose from:      │
│   • Gallery         │
│   • Google Photos   │
│   • Files           │
└─────────────────────┘
```

### **Android TV**

```
Gallery Button → Opens file browser
┌─────────────────────┐
│  🎮 Navigate with   │
│     remote D-pad    │
│                     │
│  ▶ Photos folder    │
│    [Photo list]     │
└─────────────────────┘
```

## ✅ Accessibility

### **Screen Reader Support**

```
Gallery Button:
  Label: "Select photo from gallery"
  Hint: "Opens device photo gallery"
  
Capture Button:
  Label: "Capture photo"
  Hint: "Take a photo with camera"
```

### **Keyboard Navigation**

```
Tab Order:
1. Gallery button 🖼️
2. Capture button 📷
3. Camera switches
4. Back button

Enter/Space: Activate button
```

## 📊 Before & After Comparison

### **Before: Single Option**

```
Problem: Camera not working?
Result: User is stuck ❌

┌─────────────────┐
│  Camera View    │
│   (broken)      │
└─────────────────┘

      📷
   [Capture]
     ONLY
     
User can't proceed →
```

### **After: Two Options**

```
Problem: Camera not working?
Solution: Use gallery! ✅

┌─────────────────┐
│  Camera View    │
│  (may be broken)│
└─────────────────┘

   🖼️      📷
[Gallery][Capture]
  NEW!    Original
  
User can always proceed →
```

## 🎉 Summary

**What changed:**
- ✅ Added 60x60px gallery button
- ✅ Placed left of capture button
- ✅ Same loading/disabled states
- ✅ Maintains visual hierarchy (capture is primary)
- ✅ Works on all platforms

**Visual hierarchy:**
1. **Primary**: 📷 Capture button (larger, center)
2. **Secondary**: 🖼️ Gallery button (smaller, left)

**Result**: Users have a **reliable fallback** when camera fails! 🎊
