import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/screens/photo_capture/capture_screen_router.dart';
import 'package:photobooth/screens/photo_capture/direct_ptp_capture_view.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/route_args.dart';
import 'package:provider/provider.dart';

import '../../fakes/fake_api_service.dart';

class _SeededAppSettingsManager extends AppSettingsManager {
  _SeededAppSettingsManager({AppSettingsModel? settings})
      : _seed = settings ??
            AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
        super(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        );

  final AppSettingsModel _seed;

  @override
  AppSettingsModel? get settings => _seed;

  @override
  bool get hasSettings => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettingsModel(cameraConnectionMode: 'direct_ptp');
  const args = CaptureRouteArgs(returnPhotoOnly: true);

  tearDown(() {
    directPtpHardwareProbeOverride = null;
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpRouter(
    WidgetTester tester, {
    required DirectPtpHardwareProbe? probe,
    AppSettingsModel? routerSettings,
    bool omitRouterSettings = false,
    bool provideSettingsManager = true,
  }) async {
    Widget home = CaptureScreenRouter(
      sessionKind: CaptureSessionKind.fotoZen,
      captureArgs: args,
      settings: omitRouterSettings ? null : (routerSettings ?? settings),
      hardwareProbe: probe,
    );
    if (provideSettingsManager) {
      home = ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => _SeededAppSettingsManager(settings: settings),
        child: home,
      );
    }
    await tester.pumpWidget(MaterialApp(home: home));
  }

  testWidgets('shows a spinner until the USB probe finishes', (tester) async {
    final gate = Completer<bool>();
    await pumpRouter(tester, probe: ({settings}) => gate.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(PhotoCaptureScreen), findsNothing);
    expect(find.byType(DirectPtpCaptureScreen), findsNothing);
    gate.complete(false);
    await unmount(tester);
  });

  testWidgets('opens CameraX when no Canon is on USB', (tester) async {
    await pumpRouter(tester, probe: ({settings}) async => false);
    await tester.pump();
    expect(find.byType(PhotoCaptureScreen), findsOneWidget);
    expect(find.byType(DirectPtpCaptureScreen), findsNothing);
    await unmount(tester);
  });

  testWidgets('opens native PTP when a Canon is on USB', (tester) async {
    await pumpRouter(tester, probe: ({settings}) async => true);
    await tester.pump();
    expect(find.byType(DirectPtpCaptureScreen), findsOneWidget);
    expect(find.byType(PhotoCaptureScreen), findsNothing);
    await unmount(tester);
  });

  testWidgets('does not resolve after the route is popped', (tester) async {
    final gate = Completer<bool>();
    await pumpRouter(tester, probe: ({settings}) => gate.future);
    await unmount(tester);
    gate.complete(true);
    await tester.pump();
    expect(find.byType(DirectPtpCaptureScreen), findsNothing);
    expect(find.byType(PhotoCaptureScreen), findsNothing);
  });

  testWidgets('reads kiosk settings from context when the router has none',
      (tester) async {
    AppSettingsModel? probed;
    final gate = Completer<bool>();
    await pumpRouter(
      tester,
      omitRouterSettings: true,
      probe: ({settings}) {
        probed = settings;
        return gate.future;
      },
    );
    expect(probed?.cameraConnectionMode, 'direct_ptp');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(false);
    await unmount(tester);
  });

  testWidgets('tolerates a tree with no AppSettingsManager', (tester) async {
    AppSettingsModel? probed;
    final gate = Completer<bool>();
    await pumpRouter(
      tester,
      omitRouterSettings: true,
      provideSettingsManager: false,
      probe: ({settings}) {
        probed = settings;
        return gate.future;
      },
    );
    expect(probed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(false);
    await unmount(tester);
  });

  testWidgets('falls back to the default USB probe when none is injected',
      (tester) async {
    await pumpRouter(tester, probe: null);
    await tester.pump();
    expect(find.byType(PhotoCaptureScreen), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('honours the global USB probe override', (tester) async {
    directPtpHardwareProbeOverride = ({settings}) async => true;
    await pumpRouter(tester, probe: ({settings}) async => false);
    await tester.pump();
    expect(find.byType(DirectPtpCaptureScreen), findsOneWidget);
    await unmount(tester);
  });
}
