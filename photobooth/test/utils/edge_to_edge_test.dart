import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/edge_to_edge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skips SystemChrome on web', () async {
    var modeCalled = false;
    var styleCalled = false;
    await enableAppEdgeToEdge(
      isWeb: true,
      setEnabledSystemUIMode: (mode, {overlays}) async {
        modeCalled = true;
      },
      setSystemUIOverlayStyle: (_) {
        styleCalled = true;
      },
    );
    expect(modeCalled, isFalse);
    expect(styleCalled, isFalse);
  });

  test('enables edge-to-edge with transparent system bars', () async {
    SystemUiMode? mode;
    List<SystemUiOverlay>? overlaysArg;
    SystemUiOverlayStyle? style;
    await enableAppEdgeToEdge(
      isWeb: false,
      setEnabledSystemUIMode: (m, {overlays}) async {
        mode = m;
        overlaysArg = overlays;
      },
      setSystemUIOverlayStyle: (s) {
        style = s;
      },
    );
    expect(mode, SystemUiMode.edgeToEdge);
    expect(overlaysArg, isNull);
    expect(style, kEdgeToEdgeOverlayStyle);
    expect(kEdgeToEdgeOverlayStyle.statusBarColor, isNull);
    expect(kEdgeToEdgeOverlayStyle.systemNavigationBarColor, isNull);
    expect(
      kEdgeToEdgeOverlayStyle.statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      kEdgeToEdgeOverlayStyle.systemNavigationBarIconBrightness,
      Brightness.light,
    );
    expect(kEdgeToEdgeOverlayStyle.systemNavigationBarContrastEnforced, isFalse);
    expect(kEdgeToEdgeOverlayStyle.systemStatusBarContrastEnforced, isFalse);
  });

  test('default SystemChrome path does not throw', () async {
    await enableAppEdgeToEdge();
  });
}
