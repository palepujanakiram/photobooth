# photobooth (monorepo root)

The Flutter application lives in **`photobooth/`**. All Dart / Flutter CLI commands should be run from that directory.

```bash
cd photobooth
flutter pub get
flutter run --debug --no-enable-impeller
```

`--no-enable-impeller` is required on the 4GB Android Mini PC / TV boxes (Amlogic). Omit it only on phones that render Impeller correctly.

Canon DSLR USB live view + shutter uses the local EDSDK sidecar. Full setup (Docker build, APK, USB permission, debug vs release) is in [`canon_sidecar/SETUP.md`](canon_sidecar/SETUP.md). Quick debug loop:

```bash
# After C++ sidecar changes (32-bit Mini PC):
cd canon_sidecar
SIDECAR_ARCHES=arm32 ./build.sh

# Then a full Flutter restart (hot reload / hot restart will not pick up JNI):
cd ../photobooth
flutter pub get
flutter run --debug --no-enable-impeller
```

Dart-only Pose/UI changes can hot-restart with `R` in the Flutter terminal. C++, Kotlin, JNI, or sidecar binary changes need you to stop `flutter run` and start it again.

CI and tooling are configured to use `photobooth` as the app root (see `.github/workflows/`).
