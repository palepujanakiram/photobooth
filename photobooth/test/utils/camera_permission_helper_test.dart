import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photobooth/utils/camera_permission_helper.dart';

void main() {
  test('isNativeMobileCameraPlatform reflects test platform', () {
    expect(isNativeMobileCameraPlatform, isA<bool>());
  });

  test('isNativeMobileCameraPlatform on android override', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(isNativeMobileCameraPlatform, isTrue);
  });

  test('isNativeMobileCameraPlatform on iOS override', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(isNativeMobileCameraPlatform, isTrue);
  });

  test('ensureCameraPermission delegates to platform helper', () async {
    expect(
      await ensureCameraPermissionForPlatform(isNativeMobile: false),
      isTrue,
    );
    expect(
      await ensureCameraPermissionForPlatform(
        isNativeMobile: false,
        requestIfNeeded: false,
      ),
      isTrue,
    );
  });

  test('ensureCameraPermissionForPlatform returns true when already granted',
      () async {
    expect(
      await ensureCameraPermissionForPlatform(
        isNativeMobile: true,
        readStatus: () async => PermissionStatus.granted,
      ),
      isTrue,
    );
  });

  test('ensureCameraPermissionForPlatform returns false when denied', () async {
    expect(
      await ensureCameraPermissionForPlatform(
        isNativeMobile: true,
        requestIfNeeded: false,
        readStatus: () async => PermissionStatus.denied,
      ),
      isFalse,
    );
  });

  test('ensureCameraPermissionForPlatform requests when needed', () async {
    var requested = false;
    expect(
      await ensureCameraPermissionForPlatform(
        isNativeMobile: true,
        readStatus: () async => PermissionStatus.denied,
        requestPermission: () async {
          requested = true;
          return PermissionStatus.granted;
        },
      ),
      isTrue,
    );
    expect(requested, isTrue);
  });

  test('primeCameraPermissionOnTermsLaunch completes off mobile', () async {
    if (!isNativeMobileCameraPlatform) {
      await expectLater(primeCameraPermissionOnTermsLaunch(), completes);
    }
  });
}
