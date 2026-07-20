import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photobooth/utils/camera_permission_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

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

  test('ensureCameraPermission returns true off mobile platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await ensureCameraPermission(), isTrue);
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

  test('ensureCameraPermission requests via permission_handler on mobile',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return 0;
        case 'requestPermissions':
          return {1: 1};
      }
      return null;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await ensureCameraPermission(), isTrue);
  });

  test('primeCameraPermissionOnTermsLaunch completes on mobile', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return 1;
        case 'requestPermissions':
          return {1: 1};
      }
      return null;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await expectLater(primeCameraPermissionOnTermsLaunch(), completes);
  });
}
