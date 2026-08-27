import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// Icon appearance for drawing behind transparent system bars.
///
/// Bar *colors* are omitted on purpose. Passing [SystemUiOverlayStyle.statusBarColor]
/// or [SystemUiOverlayStyle.systemNavigationBarColor] makes Flutter's Android
/// embedding call the Android 15-deprecated `Window.setStatusBarColor` /
/// `setNavigationBarColor` APIs that Play Console flags.
const SystemUiOverlayStyle kEdgeToEdgeOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

/// Puts the app in edge-to-edge on Android 10–14 so it matches Android 15+'s default.
///
/// No-op on web. Flutter already reports the resulting insets via [MediaQuery].
Future<void> enableAppEdgeToEdge({
  @visibleForTesting bool? isWeb,
  @visibleForTesting
  Future<void> Function(SystemUiMode mode, {List<SystemUiOverlay>? overlays})?
      setEnabledSystemUIMode,
  @visibleForTesting void Function(SystemUiOverlayStyle style)?
      setSystemUIOverlayStyle,
}) async {
  if (isWeb ?? kIsWeb) return;
  await (setEnabledSystemUIMode ?? SystemChrome.setEnabledSystemUIMode)(
    SystemUiMode.edgeToEdge,
  );
  (setSystemUIOverlayStyle ?? SystemChrome.setSystemUIOverlayStyle)(
    kEdgeToEdgeOverlayStyle,
  );
}
