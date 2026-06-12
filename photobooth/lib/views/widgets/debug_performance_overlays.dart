import 'package:flutter/material.dart';

import '../../utils/app_runtime_config.dart';
import '../../utils/constants.dart';
import '../../utils/debug_hud_route_policy.dart';
import 'debug_log_overlay.dart';
import 'debug_ram_monitor_overlay.dart';
import 'flow_trace_overlay.dart';

/// Whether the global on-screen debug HUD should be visible on [routeName].
bool debugHudEnabledForRoute(String? routeName) {
  return AppConstants.kShowDebugHud && debugHudAllowedOnRoute(routeName);
}

double debugHudLogPanelWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w < 520 ? (w * 0.42).clamp(200.0, 300.0) : 320.0;
}

/// Pinned debug HUD panels (RAM / JS heap + Perf trace left, Logs right).
Widget _debugHudPanels(BuildContext context) {
  final top = MediaQuery.paddingOf(context).top + 8;
  final logWidth = debugHudLogPanelWidth(context);

  return ExcludeFocus(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 8,
          top: top,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DebugRamMonitorOverlay(),
              SizedBox(height: 8),
              FlowTraceOverlay(width: 300, maxVisibleLines: 8),
            ],
          ),
        ),
        Positioned(
          right: 8,
          top: top,
          child: DebugLogOverlay(
            width: logWidth,
            maxVisibleLines: 12,
          ),
        ),
      ],
    ),
  );
}

/// Global capture → output debug HUD when `showGenerationCommentary` is on
/// (not on splash/terms).
///
/// Panels are pinned to the **top** of the screen so bottom action buttons (Capture,
/// Continue, Start Your Experience) stay tappable.
class DebugPerformanceOverlayScope extends StatelessWidget {
  const DebugPerformanceOverlayScope({
    super.key,
    required this.child,
    this.routeName,
  });

  final Widget child;
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppRuntimeConfig.instance,
      builder: (context, _) {
        if (!debugHudEnabledForRoute(routeName)) return child;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            child,
            _debugHudPanels(context),
          ],
        );
      },
    );
  }
}

/// Legacy wrapper kept for direct widget tests (respects [AppConstants.kShowDebugHud]).
class DebugPerformanceOverlays extends StatelessWidget {
  const DebugPerformanceOverlays({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppRuntimeConfig.instance,
      builder: (context, _) {
        if (!AppConstants.kShowDebugHud) {
          return const SizedBox.shrink();
        }
        return _debugHudPanels(context);
      },
    );
  }
}
