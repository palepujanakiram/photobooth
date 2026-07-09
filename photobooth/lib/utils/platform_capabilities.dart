import 'package:flutter/foundation.dart';

/// Android / iOS native builds (not web or desktop).
bool get isMobileNativePlatform {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return false;
  }
}

/// Windows / macOS / Linux Flutter desktop (not web).
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Live [CameraController] preview (mobile native + Flutter web camera plugin).
bool get supportsLiveCameraPreview => isMobileNativePlatform || kIsWeb;

/// Terms idle-time camera enumeration (native permission + web getUserMedia warm-up).
bool get supportsTermsCameraPriming => isMobileNativePlatform || kIsWeb;

/// Desktop uses [ImagePicker] (camera or gallery) instead of the `camera` plugin.
bool get usesDesktopPhotoPicker => isDesktopPlatform;

/// [webview_flutter] is only wired for mobile + web in this app.
bool get supportsEmbeddedWebView => isMobileNativePlatform || kIsWeb;

/// Firebase + FCM (project configured for Android/iOS only).
bool get supportsFirebaseMessaging => isMobileNativePlatform;

/// Native Bugsnag SDK (Android/iOS).
bool get supportsBugsnagNative => isMobileNativePlatform;
