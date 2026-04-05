import 'package:flutter/widgets.dart';
import 'app_device_type.dart';
import 'device_classifier_io.dart' if (dart.library.html) 'device_classifier_web.dart' as impl;

/// Single place for device type detection (iOS/Android phone vs tablet vs TV).
/// Uses device_info_plus and screen size; on web returns [AppDeviceType.unknown].
class DeviceClassifier {
  static Future<AppDeviceType> getDeviceType(BuildContext context) async {
    return impl.getDeviceType(context);
  }

  /// True for tablet or TV types: show only external cameras.
  static bool showOnlyExternalCameras(AppDeviceType type) {
    switch (type) {
      case AppDeviceType.iosTablet:
      case AppDeviceType.iosTv:
      case AppDeviceType.androidTablet:
      case AppDeviceType.androidTv:
        return true;
      case AppDeviceType.iosPhone:
      case AppDeviceType.androidPhone:
      case AppDeviceType.unknown:
        return false;
    }
  }
}
