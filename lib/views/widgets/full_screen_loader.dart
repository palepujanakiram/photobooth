import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Centered loader with a compact gray panel (spinner; optional status text and timer).
/// Debug-style lines (status, timer, subtitle, current process) follow [AppConstants.kshowDebugInfo].
/// [hint] is always shown when set. The rest of the screen stays clear; taps are blocked.
class FullScreenLoader extends StatelessWidget {
  final String text;
  final Color loaderColor;
  /// When set, used as the **panel** background (not a full-screen scrim).
  final Color? backgroundColor;
  final Color? textColor;
  final int? elapsedSeconds;
  final String? subtitle;
  final String? currentProcess;
  final String? hint;

  const FullScreenLoader({
    super.key,
    required this.text,
    this.loaderColor = CupertinoColors.systemBlue,
    this.backgroundColor,
    this.textColor,
    this.elapsedSeconds,
    this.subtitle,
    this.currentProcess,
    this.hint,
  });

  static Color _defaultPanelColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.dark) {
      return const Color(0xE63A3A3C);
    }
    return const Color(0xE65C5C5C);
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor = textColor ?? CupertinoColors.white;
    final panelColor = backgroundColor ?? _defaultPanelColor(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(color: Colors.transparent, dismissible: false),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: panelColor,
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(
                        radius: 20,
                        color: loaderColor,
                      ),
                      if (AppConstants.kshowDebugInfo) ...[
                        const SizedBox(height: 20),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: resolvedTextColor,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 14,
                              color: resolvedTextColor.withValues(alpha: 0.85),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (elapsedSeconds != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.timer,
                                color: resolvedTextColor.withValues(alpha: 0.9),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(elapsedSeconds!),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: resolvedTextColor,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (currentProcess != null &&
                            currentProcess!.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CupertinoActivityIndicator(
                                    radius: 8,
                                    color: resolvedTextColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    currentProcess!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: resolvedTextColor,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      if (hint != null && hint!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          hint!,
                          style: TextStyle(
                            fontSize: 13,
                            color: resolvedTextColor.withValues(alpha: 0.75),
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
