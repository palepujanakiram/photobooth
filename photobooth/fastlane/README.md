fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### firebase_all

```sh
[bundle exec] fastlane firebase_all
```

Build and upload both Android and iOS to Firebase

----


## Android

### android build_apk

```sh
[bundle exec] fastlane android build_apk
```

Build Android APK

### android build_aab

```sh
[bundle exec] fastlane android build_aab
```

Build Android App Bundle (AAB)

### android firebase_android

```sh
[bundle exec] fastlane android firebase_android
```

Build and upload Android APK to Firebase App Distribution

### android firebase_android_aab

```sh
[bundle exec] fastlane android firebase_android_aab
```

Build and upload Android App Bundle to Firebase App Distribution

----


## iOS

### ios build_ipa

```sh
[bundle exec] fastlane ios build_ipa
```

Build iOS IPA

### ios firebase_ios

```sh
[bundle exec] fastlane ios firebase_ios
```

Build and upload iOS IPA to Firebase App Distribution

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
