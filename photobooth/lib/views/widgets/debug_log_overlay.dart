import 'package:flutter/material.dart';

import '../../utils/debug_overlay_clipboard.dart';
import '../../utils/logger.dart';

class DebugLogOverlay extends StatefulWidget {
  const DebugLogOverlay({
    super.key,
    this.maxVisibleLines = 18,
    this.width = 520,
  });

  final int maxVisibleLines;
  final double width;

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  bool _collapsed = true;
  bool _errorsOnly = false;

  List<String> _filteredLines(List<String> lines) {
    if (!_errorsOnly) return lines;
    return lines
        .where((l) => l.startsWith('[ERROR]') || l.startsWith('[WARNING]'))
        .toList();
  }

  List<String> _visibleLines(List<String> filtered) {
    if (!_collapsed) return filtered;
    if (filtered.length <= widget.maxVisibleLines) return filtered;
    return filtered.sublist(filtered.length - widget.maxVisibleLines);
  }

  double get _panelMaxHeight => _collapsed ? 220 : 460;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: AppLogger.recentLinesListenable,
      builder: (context, lines, _) {
        final visible = _visibleLines(_filteredLines(lines));
        final text =
            visible.isEmpty ? '— logs will appear here —' : visible.join('\n');

        return Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.width),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Logs',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
                                        _filteredLines(lines).join('\n'),
                                        feedback: 'Logs copied',
                                      ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
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
                              onPressed: () =>
                                  setState(() => _errorsOnly = !_errorsOnly),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _errorsOnly ? 'Errors' : 'All',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _collapsed = !_collapsed),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
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
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: _panelMaxHeight),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          height: 1.25,
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
