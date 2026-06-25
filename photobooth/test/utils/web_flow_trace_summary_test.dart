import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/web_flow_trace_summary.dart';

void main() {
  const sampleTrace = <String>[
    '      ── capture ──',
    '     1 ms  CAPTURE | shutter_begin kIsWeb=true',
    '     1 ms  CAPTURE | takePicture_start',
    '    50 ms  CAPTURE | takePicture_done pathLen=64',
    '    51 ms  CAPTURE | photoModel_set photoId=abc',
    '    51 ms  UPLOAD_PREP | kickoff photoId=abc',
    '    52 ms  CAPTURE | finally isCapturing=false',
    '   593 ms  UPLOAD_PREP | encode_done len=67099',
    '  4055 ms  UPLOAD | begin sessionId=xyz kIsWeb=true',
    '  4264 ms  UPLOAD | success',
    '  4264 ms  NAV | pushReplacementNamed theme-selection start',
    '  7499 ms  GENERATE | begin theme=BW parallel=1 attempt=1',
    ' 52339 ms  OUTPUT | result_ready images=1',
  ];

  test('parseFlowTraceEvents ignores marker lines', () {
    final events = parseFlowTraceEvents(sampleTrace);
    expect(events, hasLength(12));
    expect(events.first.phase, 'CAPTURE');
    expect(events.first.ms, 1);
  });

  test('buildFlowPhaseSummaries matches expected phases', () {
    final rows = buildFlowPhaseSummaries(sampleTrace);
    expect(rows.map((r) => r.label).toList(), [
      'Capture',
      'Prep encode',
      'Wait',
      'Upload',
      'Theme',
      'Generate',
      'Total',
    ]);

    expect(rows[0].durationMs, 51);
    expect(rows[1].durationMs, 542);
    expect(rows[2].durationMs, 3462);
    expect(rows[3].durationMs, 209);
    expect(rows[4].durationMs, 3235);
    expect(rows[5].durationMs, 44840);
    expect(rows[6].durationMs, 52338);
  });

  test('buildFlowEndToEndSummaryLines formats overlay block', () {
    final lines = buildFlowEndToEndSummaryLines(sampleTrace);
    expect(lines.first, '── E2E summary ──');
    expect(lines.any((l) => l.startsWith('Capture')), isTrue);
    expect(lines.any((l) => l.startsWith('Total')), isTrue);
    expect(lines.last, contains('~52s'));
  });

  test('formatFlowDuration uses ms or seconds', () {
    expect(formatFlowDuration(51), '~51ms');
    expect(formatFlowDuration(209), '~209ms');
    expect(formatFlowDuration(3462), '~3.5s');
    expect(formatFlowDuration(44840), '~45s');
  });
}
