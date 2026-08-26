import 'dart:async';

import 'package:photobooth/utils/logger.dart';

/// Wraps every test in the suite (picked up automatically by `flutter test`).
///
/// [AppLogger] mirrors each line to the console so Dart logs reach `adb logcat`
/// on a booth — `dart:developer` alone is delivered to the VM service and never
/// shows up there. That mirror is worth ~900 extra lines across this suite,
/// which buries the actual test output, so it is off while testing.
///
/// A test that asserts on the mirror can turn it back on for its own duration;
/// [AppLogger.mirrorLogsToConsole] is visible for exactly that.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppLogger.mirrorLogsToConsole = false;
  await testMain();
}
