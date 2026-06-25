import 'package:flutter/material.dart';

import '../../utils/debug_overlay_clipboard.dart';
import '../../utils/web_flow_trace.dart';
import '../../utils/web_flow_trace_summary.dart';

/// On-screen perf timeline fed by [WebFlowTrace] when debug logging is enabled.
class FlowTraceOverlay extends StatefulWidget {
  const FlowTraceOverlay({
    super.key,
    this.maxVisibleLines = 14,
    this.width = 420,
  });

  final int maxVisibleLines;
  final double width;

  @override
  State<FlowTraceOverlay> createState() => _FlowTraceOverlayState();
}

class _FlowTraceOverlayState extends State<FlowTraceOverlay> {
  bool _collapsed = true;

  List<String> _visibleLines(List<String> lines) {
    if (!_collapsed) return lines;
    if (lines.length <= widget.maxVisibleLines) return lines;
    return lines.sublist(lines.length - widget.maxVisibleLines);
  }

  double get _panelMaxHeight => _collapsed ? 200 : 380;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: WebFlowTrace.linesListenable,
      builder: (context, lines, _) {
        final visible = _visibleLines(lines);
        final summaryLines = buildFlowEndToEndSummaryLines(lines);
        final summaryText = summaryLines.isEmpty
            ? ''
            : '${summaryLines.join('\n')}\n';
        final traceText = visible.isEmpty
            ? '— perf trace (capture → output) —'
            : visible.join('\n');
        final text = '$summaryText$traceText';
        final copyText = summaryLines.isEmpty
            ? lines.join('\n')
            : '${summaryLines.join('\n')}\n\n${lines.join('\n')}';

        return Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.width),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Perf trace',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 0,
                          runSpacing: 0,
                          children: [
                            TextButton(
                              onPressed: lines.isEmpty
                                  ? null
                                  : () => copyDebugPanelText(
                                        context,
                                        copyText,
                                        feedback: 'Perf trace copied',
                                      ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Copy',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: WebFlowTrace.clearOverlay,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _collapsed = !_collapsed),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _collapsed ? 'Expand' : 'Collapse',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: _panelMaxHeight),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          height: 1.3,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
