fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android generatebuild

```sh
[bundle exec] fastlane android generatebuild
```

Sync version, build AAB and APK, upload AAB to Play Console internal, and log both paths

### android firebase

```sh
[bundle exec] fastlane android firebase
```

Upload the existing release APK to Firebase App Tester (no Play upload, no version bump)

### android build

```sh
[bundle exec] fastlane android build
```

Sync version and build release AAB only (no upload)

----


## iOS

### ios generatebuild

```sh
[bundle exec] fastlane ios generatebuild
```

Sync version, build release IPA, and upload to App Store Connect (TestFlight)

### ios build

```sh
[bundle exec] fastlane ios build
```

Sync version and build release IPA only (no upload)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
