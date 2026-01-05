# Fastlane Configuration for Photo Booth App

This directory contains Fastlane configuration files for building and distributing the Photo Booth app to Firebase App Distribution.

## Prerequisites

1. **Fastlane installed**: 
   ```bash
   sudo gem install fastlane
   ```

2. **Firebase CLI installed**:
   ```bash
   npm install -g firebase-tools
   ```

3. **Firebase App Distribution plugin**:
   ```bash
   fastlane add_plugin firebase_app_distribution
   ```

4. **Firebase authentication**:
   ```bash
   # For Android Firebase account
   firebase login:ci --project YOUR_ANDROID_PROJECT_ID
   
   # For iOS Firebase account  
   firebase login:ci --project YOUR_IOS_PROJECT_ID
   ```
   Copy the tokens and add them to `fastlane/Appfile` (see Configuration section below).

## Quick Setup

1. **Get your Firebase tokens** (separate for iOS and Android accounts):
   ```bash
   # For Android Firebase account
   firebase login:ci --project YOUR_ANDROID_PROJECT_ID
   # Copy the Android token
   
   # For iOS Firebase account
   firebase login:ci --project YOUR_IOS_PROJECT_ID
   # Copy the iOS token
   ```

2. **Edit `fastlane/Appfile`** and update all Firebase configuration:
   - Firebase App IDs (Android and iOS)
   - Firebase tokens (Android and iOS)
   - Test groups (Android and iOS)
   - Release notes (Android and iOS)
   
   See the Configuration section below for details.

## Configuration

All Firebase configuration is now in `fastlane/Appfile` to support separate Firebase accounts for iOS and Android. Edit `fastlane/Appfile` and update all values:

### Firebase App IDs

```ruby
# Android Firebase App ID (from Android Firebase project)
def firebase_android_app_id
  "1:123456789:android:abcdef123456" # Replace with your Android Firebase App ID
end

# iOS Firebase App ID (from iOS Firebase project)
def firebase_ios_app_id
  "1:123456789:ios:abcdef123456" # Replace with your iOS Firebase App ID
end
```

### Firebase Tokens (Separate for iOS and Android)

```ruby
# Android Firebase token (from Android Firebase account)
def firebase_android_token
  "your_android_firebase_token_here" # Get from: firebase login:ci (Android Firebase account)
end

# iOS Firebase token (from iOS Firebase account)
def firebase_ios_token
  "your_ios_firebase_token_here" # Get from: firebase login:ci (iOS Firebase account)
end
```

### Test Groups (Separate for iOS and Android)

```ruby
# Android test groups
def firebase_android_test_groups
  "testers,qa-team" # Comma-separated list of test groups for Android
end

# iOS test groups
def firebase_ios_test_groups
  "testers,qa-team" # Comma-separated list of test groups for iOS
end
```

### Release Notes (Separate for iOS and Android)

```ruby
# Android release notes
def firebase_android_release_notes
  "Version 0.1.0 - Android build" # Release notes for Android builds
end

# iOS release notes
def firebase_ios_release_notes
  "Version 0.1.0 - iOS build" # Release notes for iOS builds
end
```

### Configuration Summary

| Setting | Android Method | iOS Method | Required |
|---------|---------------|------------|----------|
| Firebase App ID | `firebase_android_app_id` | `firebase_ios_app_id` | ✅ Yes |
| Firebase Token | `firebase_android_token` | `firebase_ios_token` | ✅ Yes |
| Test Groups | `firebase_android_test_groups` | `firebase_ios_test_groups` | ⚠️ Optional |
| Release Notes | `firebase_android_release_notes` | `firebase_ios_release_notes` | ⚠️ Optional |

### Required for Android Signing (if not using debug signing)

```bash
ANDROID_KEYSTORE_PATH=/path/to/keystore.jks
ANDROID_KEYSTORE_PASSWORD=your_keystore_password
ANDROID_KEY_ALIAS=your_key_alias
ANDROID_KEY_PASSWORD=your_key_password
```

### Required for iOS (if building iOS)

```bash
IOS_BUNDLE_ID=com.example.photobooth
IOS_PROVISIONING_PROFILE_NAME=Your_Provisioning_Profile_Name
```

## Usage

### Android

**Build APK only:**
```bash
fastlane android build_apk
```

**Build App Bundle (AAB) only:**
```bash
fastlane android build_aab
```

**Build and upload APK to Firebase:**
```bash
fastlane android firebase_android
```

**Build and upload AAB to Firebase:**
```bash
fastlane android firebase_android_aab
```

### iOS

**Build IPA only:**
```bash
fastlane ios build_ipa
```

**Build and upload IPA to Firebase:**
```bash
fastlane ios firebase_ios
```

### Both Platforms

**Build and upload both Android and iOS:**
```bash
fastlane firebase_all
```

## Getting Firebase App IDs

Since we use separate Firebase accounts for iOS and Android:

### Getting Firebase App IDs

#### For Android Firebase Account:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your **Android Firebase project**
3. Go to Project Settings (gear icon)
4. Scroll down to "Your apps" section
5. Find your Android app
6. Copy the App ID (format: `1:123456789:android:abcdef123456`)
7. Update `firebase_android_app_id` in `fastlane/Appfile`

#### For iOS Firebase Account:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your **iOS Firebase project**
3. Go to Project Settings (gear icon)
4. Scroll down to "Your apps" section
5. Find your iOS app
6. Copy the App ID (format: `1:123456789:ios:abcdef123456`)
7. Update `firebase_ios_app_id` in `fastlane/Appfile`

### Getting Firebase Tokens

Since you have separate Firebase accounts, you need separate tokens:

#### For Android Firebase Account:
```bash
firebase login:ci --project YOUR_ANDROID_PROJECT_ID
```
Copy the token and update `firebase_android_token` in `fastlane/Appfile`.

#### For iOS Firebase Account:
```bash
firebase login:ci --project YOUR_IOS_PROJECT_ID
```
Copy the token and update `firebase_ios_token` in `fastlane/Appfile`.

## Setting up Firebase Test Groups

1. Go to Firebase Console > App Distribution
2. Click on "Testers & Groups"
3. Create groups (e.g., "testers", "qa-team")
4. Add testers to groups
5. Use group names in `FIREBASE_TEST_GROUPS` environment variable

## Troubleshooting

### Firebase Authentication Issues

If you get authentication errors:
```bash
firebase logout
firebase login:ci
```

### Android Build Issues

- Ensure `ANDROID_HOME` is set correctly
- Check that signing credentials are correct
- Verify `local.properties` has correct paths

### iOS Build Issues

- Ensure Xcode command line tools are installed: `xcode-select --install`
- Verify provisioning profiles are installed
- Check that certificates are valid in Keychain

## Notes

- The current configuration uses debug signing for Android. For production, update the signing configuration in `android/app/build.gradle` and set the environment variables.
- For iOS App Store builds, change `export_method` from "ad-hoc" to "app-store" in the Fastfile.
- Build artifacts are saved in `android/app/build/outputs/` for Android and `./build/ios/ipa/` for iOS.

