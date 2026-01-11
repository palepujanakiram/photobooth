# UVCCamera Manual Setup Instructions

## Problem
JitPack cannot build the UVCCamera library (all commits show "Error" status). We need to include it manually.

## Solution Options

### Option 1: Include as Git Submodule (Recommended)

1. Add UVCCamera as a submodule:
```bash
cd android/app
git submodule add https://github.com/saki4510t/UVCCamera.git libs/UVCCamera
```

2. Update `android/app/build.gradle`:
```gradle
dependencies {
    implementation 'com.serenegiant:common:4.1.1'
    implementation project(':libs:UVCCamera:libuvccamera')
}
```

3. Update `android/settings.gradle`:
```gradle
include ':libs:UVCCamera:libuvccamera'
```

### Option 2: Download and Include AAR

1. Download pre-built AAR (if available) or build from source
2. Place in `android/app/libs/`
3. Update `android/app/build.gradle`:
```gradle
dependencies {
    implementation 'com.serenegiant:common:4.1.1'
    implementation files('libs/uvccamera.aar')
}
```

### Option 3: Use Alternative Library

Consider using a different UVC library that works with JitPack or Maven Central.

## Temporary Workaround

For now, the code is set up to work with UVCCamera. Once you include the library manually using one of the options above, it should work.
