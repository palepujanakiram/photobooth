import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/web_flow_trace.dart';
import 'package:photobooth/views/widgets/flow_trace_overlay.dart';

void main() {
  setUp(() {
    AppConstants.testEnableLogOutputOverride = true;
  });

  tearDown(() {
    AppConstants.testEnableLogOutputOverride = null;
    WebFlowTrace.clearOverlay();
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
  });

  test('WebFlowTrace buffers overlay lines when commentary enabled', () {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    WebFlowTrace.clearOverlay();
    WebFlowTrace.reset(label: 'test');
    WebFlowTrace.log('PHASE', 'detail');

    expect(WebFlowTrace.linesListenable.value, isNotEmpty);
    expect(WebFlowTrace.linesListenable.value.last, contains('PHASE'));
    expect(WebFlowTrace.linesListenable.value.last, contains('detail'));
  });

  testWidgets('FlowTraceOverlay shows recent trace lines', (tester) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    WebFlowTrace.clearOverlay();
    WebFlowTrace.reset(label: 'widget');
    WebFlowTrace.log('CAPTURE', 'shutter');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FlowTraceOverlay())),
    );

    expect(find.textContaining('CAPTURE'), findsOneWidget);
    expect(find.textContaining('shutter'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('FlowTraceOverlay shows E2E summary when milestones exist', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    WebFlowTrace.clearOverlay();
    WebFlowTrace.reset(label: 'capture');
    WebFlowTrace.log('CAPTURE', 'shutter_begin');
    WebFlowTrace.log('CAPTURE', 'finally isCapturing=false');
    WebFlowTrace.log('UPLOAD_PREP', 'kickoff photoId=x');
    WebFlowTrace.log('UPLOAD_PREP', 'encode_done len=1');
    WebFlowTrace.log('UPLOAD', 'begin sessionId=x');
    WebFlowTrace.log('NAV', 'pushReplacementNamed theme-selection start');
    WebFlowTrace.log('GENERATE', 'begin theme=BW');
    WebFlowTrace.log('OUTPUT', 'result_ready images=1');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FlowTraceOverlay())),
    );

    expect(find.textContaining('E2E summary'), findsOneWidget);
    expect(find.textContaining('Capture'), findsOneWidget);
    expect(find.textContaining('Total'), findsOneWidget);
  });
}
