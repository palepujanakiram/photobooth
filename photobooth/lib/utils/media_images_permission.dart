import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:permission_handler/permission_handler.dart';

import 'logger.dart';

/// First Android release with `READ_MEDIA_IMAGES`. Below it, the media library
/// is behind `READ_EXTERNAL_STORAGE`.
const int kReadMediaImagesSdk = 33;

/// Which permission actually grants read access to the photo library here.
///
/// Android split this at 13: `READ_MEDIA_IMAGES` does not exist below SDK 33,
/// and `READ_EXTERNAL_STORAGE` is declared `maxSdkVersion="32"` in the
/// manifest for exactly that reason. `permission_handler` maps
/// [Permission.photos] to the former and [Permission.storage] to the latter, so
/// one of them is always the wrong question to ask.
///
/// Asking the wrong one is **not an error** — the request resolves without
/// showing anything and the status stays denied. On screen that reads as a
/// "Grant access" button that ignores taps, which is what an Android 11 box
/// did while the same code worked on an Android 13 phone.
///
/// iOS has no such split, and [Permission.photos] is correct there.
Future<Permission> resolveMediaImagesPermission({
  @visibleForTesting int? androidSdkOverride,
}) async {
  // An override means "answer as though this were Android SDK N", so it stands
  // in for the platform check too — otherwise a test on a desktop host can only
  // ever see the iOS answer.
  if (androidSdkOverride != null) {
    return androidSdkOverride >= kReadMediaImagesSdk
        ? Permission.photos
        : Permission.storage;
  }
  if (kIsWeb || !Platform.isAndroid) return Permission.photos;
  final sdk = await _androidSdk();
  return sdk >= kReadMediaImagesSdk ? Permission.photos : Permission.storage;
}

/// Reads the permission's current state, asking the right one for this OS.
Future<PermissionStatus> readMediaImagesPermission() async {
  return (await resolveMediaImagesPermission()).status;
}

/// Requests it, asking the right one for this OS.
Future<PermissionStatus> requestMediaImagesPermission() async {
  return (await resolveMediaImagesPermission()).request();
}

Future<int> _androidSdk() async {
  try {
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  } catch (e) {
    // Unknown version: assume modern, because asking for READ_MEDIA_IMAGES on
    // an older device fails harmlessly, while asking for a storage permission
    // the manifest caps at SDK 32 would be rejected outright on a new one.
    AppLogger.debug('Could not read the Android SDK level: $e');
    return kReadMediaImagesSdk;
  }
}
