import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/camera_permission_helper.dart';

void main() {
  test('ensureCameraPermission returns true on non-mobile platforms', () async {
    if (!isNativeMobileCameraPlatform) {
      expect(await ensureCameraPermission(), isTrue);
      expect(await ensureCameraPermission(requestIfNeeded: false), isTrue);
      await expectLater(primeCameraPermissionOnTermsLaunch(), completes);
    }
  });
}
