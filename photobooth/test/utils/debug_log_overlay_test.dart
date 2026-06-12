import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/logger.dart';
import 'package:photobooth/views/widgets/debug_log_overlay.dart';
import 'package:photobooth/views/widgets/debug_performance_overlays.dart';

void main() {
  setUp(() {
    AppConstants.testEnableLogOutputOverride = true;
  });

  tearDown(() {
    AppConstants.testEnableLogOutputOverride = null;
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
  });

  testWidgets('DebugLogOverlay shows buffered AppLogger debug lines by default',
      (tester) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    AppLogger.debug('generation started');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DebugLogOverlay())),
    );

    expect(find.textContaining('generation started'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('DebugPerformanceOverlays hides HUD when commentary off', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    AppLogger.debug('should not show hud');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DebugPerformanceOverlays(),
        ),
      ),
    );

    expect(find.text('Logs'), findsNothing);
    expect(find.text('Perf trace'), findsNothing);
  });

  testWidgets('DebugPerformanceOverlays mounts log panel when commentary on',
      (tester) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    AppLogger.debug('visible in hud');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DebugPerformanceOverlays(),
        ),
      ),
    );

    expect(find.text('Logs'), findsOneWidget);
    expect(find.textContaining('visible in hud'), findsOneWidget);
    expect(find.text('Perf trace'), findsOneWidget);
    expect(find.textContaining('RAM (RSS)'), findsOneWidget);
  });

  testWidgets('DebugPerformanceOverlayScope hides HUD on terms route', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    AppLogger.debug('hidden on terms');

    await tester.pumpWidget(
      MaterialApp(
        home: DebugPerformanceOverlayScope(
          routeName: AppConstants.kRouteTerms,
          child: const Scaffold(body: Text('terms')),
        ),
      ),
    );

    expect(find.text('Logs'), findsNothing);
    expect(find.text('Perf trace'), findsNothing);
  });

  testWidgets('DebugPerformanceOverlayScope shows HUD on capture route', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    AppLogger.debug('visible on capture');

    await tester.pumpWidget(
      MaterialApp(
        home: DebugPerformanceOverlayScope(
          routeName: AppConstants.kRouteCapture,
          child: const Scaffold(body: Text('capture')),
        ),
      ),
    );

    expect(find.text('Logs'), findsOneWidget);
    expect(find.textContaining('visible on capture'), findsOneWidget);
  });

  testWidgets('DebugPerformanceOverlayScope shows HUD above routes', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    AppLogger.debug('scope hud line');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DebugPerformanceOverlayScope(
          routeName: AppConstants.kRouteCapture,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('route body')),
      ),
    );

    expect(find.text('route body'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.textContaining('scope hud line'), findsOneWidget);
  });
}
