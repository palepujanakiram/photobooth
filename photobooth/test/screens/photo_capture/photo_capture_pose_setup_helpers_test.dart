import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_pose_setup_helpers.dart';
import 'package:photobooth/utils/app_device_type.dart';

void main() {
  test('kioskShouldTryUvcBeforeCameraX for TV and tablet only', () {
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidTv), isTrue);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidTablet), isTrue);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidPhone), isFalse);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.iosPhone), isFalse);
    expect(kioskShouldTryUvcBeforeCameraX(null), isFalse);
  });
}
