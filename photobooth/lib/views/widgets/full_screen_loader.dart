import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/app_runtime_config.dart';
import '../../utils/constants.dart';

/// Centered loader with a compact gray panel (spinner + status text).
///
/// [text] and [subtitle] are always shown. Elapsed time uses [autonomousElapsed]
/// (self-ticking) or [elapsedSeconds] from the parent when [AppConstants.kshowDebugInfo].
/// [currentProcess] is debug-only commentary.
class FullScreenLoader extends StatefulWidget {
  final String text;
  final Color loaderColor;
  /// When set, used as the **panel** background (not a full-screen scrim).
  final Color? backgroundColor;
  final Color? textColor;
  final int? elapsedSeconds;
  /// When true, ticks elapsed time locally (keeps updating during parent rebuild gaps).
  final bool autonomousElapsed;
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
    this.autonomousElapsed = false,
    this.subtitle,
    this.currentProcess,
    this.hint,
  });

  @override
  State<FullScreenLoader> createState() => _FullScreenLoaderState();
}

class _FullScreenLoaderState extends State<FullScreenLoader> {
  Timer? _elapsedTimer;
  int _autonomousElapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autonomousElapsed) {
      _startAutonomousElapsedTimer();
    }
  }

  @override
  void didUpdateWidget(covariant FullScreenLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autonomousElapsed && _elapsedTimer == null) {
      _startAutonomousElapsedTimer();
    } else if (!widget.autonomousElapsed) {
      _stopAutonomousElapsedTimer();
    }
  }

  @override
  void dispose() {
    _stopAutonomousElapsedTimer();
    super.dispose();
  }

  void _startAutonomousElapsedTimer() {
    _autonomousElapsedSeconds = 0;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _autonomousElapsedSeconds++);
    });
  }

  void _stopAutonomousElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

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

  int? _resolvedElapsedSeconds(bool showDebugElapsed) {
    if (widget.autonomousElapsed) return _autonomousElapsedSeconds;
    if (showDebugElapsed) return widget.elapsedSeconds;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor = widget.textColor ?? CupertinoColors.white;
    final panelColor = widget.backgroundColor ?? _defaultPanelColor(context);

    return FocusScope(
      canRequestFocus: false,
      skipTraversal: true,
      child: Stack(
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
                        color: widget.loaderColor,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.text,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: resolvedTextColor,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 14,
                            color: resolvedTextColor.withValues(alpha: 0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      ListenableBuilder(
                        listenable: AppRuntimeConfig.instance,
                        builder: (context, _) {
                          final showDebugElapsed = AppConstants.kshowDebugInfo;
                          final elapsed = _resolvedElapsedSeconds(showDebugElapsed);
                          final showCurrentProcess = showDebugElapsed &&
                              widget.currentProcess != null &&
                              widget.currentProcess!.isNotEmpty;

                          if (elapsed == null && !showCurrentProcess) {
                            return const SizedBox.shrink();
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (elapsed != null) ...[
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
                                      _formatTime(elapsed),
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
                              if (showCurrentProcess) ...[
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
                                          widget.currentProcess!,
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
                          );
                        },
                      ),
                      if (widget.hint != null && widget.hint!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          widget.hint!,
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
      ),
    );
  }
}
