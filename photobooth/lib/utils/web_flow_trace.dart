import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'coalesced_string_list_notifier.dart';
import 'constants.dart';

/// Timestamped phases for debugging capture → upload → generate → result.
///
/// **Console:** filter by `WebFlow` in DevTools / terminal (`kDebugMode` or
/// [AppConstants.kEnableLogOutput]).
///
/// **On-screen:** when [AppConstants.kShowDebugHud] is true (`showGenerationCommentary`),
/// lines also appear in [FlowTraceOverlay] via [linesListenable].
///
/// Call [reset] once at shutter to start an end-to-end timeline.
class WebFlowTrace {
  WebFlowTrace._();

  static const int _maxBufferedLines = 80;
  static int _epochMs = 0;

  static final CoalescedStringListNotifier _linesBuffer =
      CoalescedStringListNotifier(maxLines: _maxBufferedLines);

  /// Recent perf-trace lines for on-screen overlay widgets.
  static ValueListenable<List<String>> get linesListenable => _linesBuffer.lines;

  static bool get _consoleActive => AppConstants.kEnableLogOutput;

  static bool get _overlayActive => AppConstants.kShowDebugHud;

  /// Clears the on-screen buffer (console history is unaffected).
  static void clearOverlay() {
    _linesBuffer.clear();
  }

  /// Start a new timeline (milliseconds relative to this call).
  static void reset({required String label}) {
    _epochMs = DateTime.now().millisecondsSinceEpoch;
    final marker = '── $label ──';
    if (_consoleActive) {
      developer.log(
        '$marker at ${DateTime.now().toIso8601String()}',
        name: 'WebFlow',
      );
    }
    if (_overlayActive) {
      _appendOverlay('      $marker');
    }
  }

  /// One phase line: elapsed ms since [reset], phase name, optional detail.
  static void log(String phase, [String detail = '']) {
    if (!_consoleActive && !_overlayActive) return;

    if (_epochMs == 0) {
      _epochMs = DateTime.now().millisecondsSinceEpoch;
    }
    final dt = DateTime.now().millisecondsSinceEpoch - _epochMs;
    final pad = dt.toString().padLeft(6);
    final tail = detail.isEmpty ? '' : ' | $detail';
    final line = '$pad ms  $phase$tail';

    if (_consoleActive) {
      developer.log(line, name: 'WebFlow');
    }
    if (_overlayActive) {
      _appendOverlay(line);
    }
  }

  static void _appendOverlay(String line) {
    _linesBuffer.appendAll(<String>[line]);
  }
}
