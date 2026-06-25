/// Builds a compact end-to-end timing summary from [WebFlowTrace] overlay lines.
library;

/// One row in the on-screen end-to-end summary.
class FlowPhaseSummaryRow {
  const FlowPhaseSummaryRow({
    required this.label,
    this.startMs,
    this.endMs,
    this.isTotal = false,
  });

  final String label;
  final int? startMs;
  final int? endMs;
  final bool isTotal;

  int? get durationMs {
    if (startMs == null || endMs == null) return null;
    return endMs! - startMs!;
  }
}

/// Parsed perf-trace event (`     1 ms  CAPTURE | detail`).
class FlowTraceEvent {
  const FlowTraceEvent({
    required this.ms,
    required this.phase,
    this.detail = '',
  });

  final int ms;
  final String phase;
  final String detail;
}

final RegExp _traceLinePattern = RegExp(
  r'^\s*(\d+)\s+ms\s+([^\s|]+)(?:\s+\|\s+(.*))?$',
);

/// Parses overlay lines into timestamped events (ignores `── marker ──` rows).
List<FlowTraceEvent> parseFlowTraceEvents(List<String> lines) {
  final events = <FlowTraceEvent>[];
  for (final line in lines) {
    final match = _traceLinePattern.firstMatch(line);
    if (match == null) continue;
    events.add(
      FlowTraceEvent(
        ms: int.parse(match.group(1)!),
        phase: match.group(2)!,
        detail: match.group(3) ?? '',
      ),
    );
  }
  return events;
}

FlowTraceEvent? _firstEvent(
  List<FlowTraceEvent> events, {
  required String phase,
  String? detailContains,
}) {
  for (final event in events) {
    if (event.phase != phase) continue;
    if (detailContains != null && !event.detail.contains(detailContains)) {
      continue;
    }
    return event;
  }
  return null;
}

FlowTraceEvent? _lastEvent(
  List<FlowTraceEvent> events, {
  required String phase,
  String? detailContains,
}) {
  FlowTraceEvent? found;
  for (final event in events) {
    if (event.phase != phase) continue;
    if (detailContains != null && !event.detail.contains(detailContains)) {
      continue;
    }
    found = event;
  }
  return found;
}

/// Human-readable duration for overlay rows.
String formatFlowDuration(int ms) {
  if (ms < 1000) return '~${ms}ms';
  final seconds = ms / 1000;
  if (seconds < 10) {
    final rounded = (seconds * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '~${text}s';
  }
  return '~${seconds.round()}s';
}

/// Derives capture → output phase rows from raw overlay lines.
List<FlowPhaseSummaryRow> buildFlowPhaseSummaries(List<String> lines) {
  final events = parseFlowTraceEvents(lines);
  if (events.isEmpty) return const [];

  final captureStart = _firstEvent(
        events,
        phase: 'CAPTURE',
        detailContains: 'shutter_begin',
      ) ??
      _firstEvent(events, phase: 'CAPTURE');
  final captureEnd = _firstEvent(
        events,
        phase: 'CAPTURE',
        detailContains: 'finally isCapturing=false',
      ) ??
      _firstEvent(events, phase: 'CAPTURE', detailContains: 'photoModel_set');
  final prepStart = _firstEvent(
    events,
    phase: 'UPLOAD_PREP',
    detailContains: 'kickoff',
  );
  final prepEnd = _lastEvent(
        events,
        phase: 'UPLOAD_PREP',
        detailContains: 'encode_done',
      ) ??
      _lastEvent(events, phase: 'UPLOAD_PREP', detailContains: 'face_done');
  final uploadStart = _firstEvent(events, phase: 'UPLOAD', detailContains: 'begin');
  final uploadEnd = _firstEvent(
        events,
        phase: 'NAV',
        detailContains: 'pushReplacementNamed theme-selection start',
      ) ??
      _firstEvent(events, phase: 'UPLOAD', detailContains: 'success');
  final generateStart = _firstEvent(events, phase: 'GENERATE', detailContains: 'begin');
  final result = _firstEvent(events, phase: 'OUTPUT', detailContains: 'result_ready');

  final rows = <FlowPhaseSummaryRow>[];

  void addRow(String label, FlowTraceEvent? start, FlowTraceEvent? end) {
    if (start == null || end == null) return;
    if (end.ms < start.ms) return;
    rows.add(
      FlowPhaseSummaryRow(
        label: label,
        startMs: start.ms,
        endMs: end.ms,
      ),
    );
  }

  addRow('Capture', captureStart, captureEnd);
  addRow('Prep encode', prepStart, prepEnd);
  if (prepEnd != null && uploadStart != null) {
    addRow('Wait', prepEnd, uploadStart);
  }
  addRow('Upload', uploadStart, uploadEnd);
  if (uploadEnd != null && generateStart != null) {
    addRow('Theme', uploadEnd, generateStart);
  }
  addRow('Generate', generateStart, result);

  if (result != null) {
    final totalStart = captureStart?.ms ?? events.first.ms;
    rows.add(
      FlowPhaseSummaryRow(
        label: 'Total',
        startMs: totalStart,
        endMs: result.ms,
        isTotal: true,
      ),
    );
  }

  return rows;
}

String _formatMs(int ms) => ms.toString().padLeft(5);

String formatFlowPhaseSummaryRow(FlowPhaseSummaryRow row) {
  final duration = row.durationMs;
  final durText = duration == null ? '—' : formatFlowDuration(duration);
  if (row.isTotal) {
    return '${row.label.padRight(10)} $durText';
  }
  if (row.startMs == null || row.endMs == null) {
    return '${row.label.padRight(10)} —  $durText';
  }
  final range = '${_formatMs(row.startMs!)}→${_formatMs(row.endMs!)}';
  return '${row.label.padRight(10)} $range  $durText';
}

/// Overlay text block: header plus aligned phase rows.
List<String> buildFlowEndToEndSummaryLines(List<String> traceLines) {
  final rows = buildFlowPhaseSummaries(traceLines);
  if (rows.isEmpty) return const [];

  return <String>[
    '── E2E summary ──',
    ...rows.map(formatFlowPhaseSummaryRow),
  ];
}
