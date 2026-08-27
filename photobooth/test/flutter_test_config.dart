import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Wraps every test in the suite (picked up automatically by `flutter test`).
///
/// - sqflite needs FFI (Android/iOS plugins are unavailable in `flutter test`).
/// - [AppLogger] mirrors each line to the console so Dart logs reach `adb logcat`
///   on a booth — `dart:developer` alone is delivered to the VM service and never
///   shows up there. That mirror is worth ~900 extra lines across this suite,
///   which buries the actual test output, so it is off while testing.
///
/// A test that asserts on the mirror can turn it back on for its own duration;
/// [AppLogger.mirrorLogsToConsole] is visible for exactly that.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppLogger.mirrorLogsToConsole = false;
  await testMain();
}
