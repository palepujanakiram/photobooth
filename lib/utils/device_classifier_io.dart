import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_device_type.dart';
import 'constants.dart';

Future<AppDeviceType> getDeviceType(BuildContext context) async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isIOS) {
    final ios = await deviceInfo.iosInfo;
    if (_isAppleTv(ios.utsname.machine)) {
      return AppDeviceType.iosTv;
    }
    return _isTablet(context) ? AppDeviceType.iosTablet : AppDeviceType.iosPhone;
  }

  if (Platform.isAndroid) {
    final android = await deviceInfo.androidInfo;
    if (_isAndroidTv(android.systemFeatures)) {
      return AppDeviceType.androidTv;
    }
    return _isTablet(context) ? AppDeviceType.androidTablet : AppDeviceType.androidPhone;
  }

  return AppDeviceType.unknown;
}

bool _isTablet(BuildContext context) {
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  return shortestSide >= AppConstants.kTabletBreakpoint;
}

bool _isAppleTv(String machine) {
  return machine.toLowerCase().contains('appletv');
}

bool _isAndroidTv(List<String> features) {
  return features.contains('android.software.leanback');
}
