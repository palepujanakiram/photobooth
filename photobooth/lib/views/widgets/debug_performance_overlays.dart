import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        MovableDebugPanel(
          prefsKeyPrefix: 'debugHud.ram',
          defaultPosition: Offset(8, top),
          panelWidth: 132,
          child: const DebugRamMonitorOverlay(),
        ),
        MovableDebugPanel(
          prefsKeyPrefix: 'debugHud.flowTrace',
          defaultPosition: Offset(8, top + 8 + 78),
          panelWidth: 300,
          child: const FlowTraceOverlay(width: 300, maxVisibleLines: 8),
        ),
        MovableDebugLogOverlay(
          defaultRight: 8,
          defaultTop: top,
          width: logWidth,
          maxVisibleLines: 12,
        ),
      ],
    ),
  );
}

/// Generic draggable wrapper for a debug HUD panel.
class MovableDebugPanel extends StatefulWidget {
  const MovableDebugPanel({
    super.key,
    required this.prefsKeyPrefix,
    required this.defaultPosition,
    required this.panelWidth,
    required this.child,
  });

  final String prefsKeyPrefix;
  final Offset defaultPosition;
  final double panelWidth;
  final Widget child;

  @override
  State<MovableDebugPanel> createState() => _MovableDebugPanelState();
}

class _MovableDebugPanelState extends State<MovableDebugPanel> {
  Offset? _pos;
  bool _loaded = false;

  String get _prefsKeyX => '${widget.prefsKeyPrefix}.x';
  String get _prefsKeyY => '${widget.prefsKeyPrefix}.y';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _loadSavedPosition();
  }

  Future<void> _loadSavedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefsKeyX);
      final y = prefs.getDouble(_prefsKeyY);
      if (!mounted) return;
      if (x != null && y != null) {
        setState(() => _pos = Offset(x, y));
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKeyX, pos.dx);
      await prefs.setDouble(_prefsKeyY, pos.dy);
    } catch (_) {
      // Best-effort only.
    }
  }

  Offset _clampToScreen(Offset pos, Size screen) {
    final maxX = (screen.width - widget.panelWidth).clamp(0.0, screen.width);
    final x = pos.dx.clamp(0.0, maxX);
    final y = pos.dy.clamp(0.0, (screen.height - 56).clamp(0.0, screen.height));
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pos = _clampToScreen(_pos ?? widget.defaultPosition, screen);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: _DragHandle(
        onDrag: (delta) {
          final next = _clampToScreen(pos + delta, screen);
          setState(() => _pos = next);
        },
        onDragEnd: () => _savePosition(_pos ?? pos),
        child: widget.child,
      ),
    );
  }
}

/// Draggable wrapper for the logs overlay so it can be moved out of the way
/// to tap UI elements underneath.
class MovableDebugLogOverlay extends StatefulWidget {
  const MovableDebugLogOverlay({
    super.key,
    required this.defaultRight,
    required this.defaultTop,
    required this.width,
    required this.maxVisibleLines,
  });

  final double defaultRight;
  final double defaultTop;
  final double width;
  final int maxVisibleLines;

  @override
  State<MovableDebugLogOverlay> createState() => _MovableDebugLogOverlayState();
}

class _MovableDebugLogOverlayState extends State<MovableDebugLogOverlay> {
  static const _prefsKeyX = 'debugHud.logOverlay.x';
  static const _prefsKeyY = 'debugHud.logOverlay.y';

  Offset? _pos;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _loadSavedPosition();
  }

  Future<void> _loadSavedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_prefsKeyX);
      final y = prefs.getDouble(_prefsKeyY);
      if (!mounted) return;
      if (x != null && y != null) {
        setState(() => _pos = Offset(x, y));
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKeyX, pos.dx);
      await prefs.setDouble(_prefsKeyY, pos.dy);
    } catch (_) {
      // Best-effort only.
    }
  }

  Offset _defaultPosition(Size screen) {
    // Default: pinned top-right, matching the previous Positioned(right/top) behavior.
    final x = (screen.width - widget.width - widget.defaultRight).clamp(0.0, screen.width);
    final y = widget.defaultTop.clamp(0.0, screen.height);
    return Offset(x, y);
  }

  Offset _clampToScreen(Offset pos, Size screen) {
    // Keep the panel on-screen. We clamp by width; height varies (collapsed/expanded),
    // so keep the top-left within bounds and allow some vertical slack.
    final maxX = (screen.width - widget.width).clamp(0.0, screen.width);
    final x = pos.dx.clamp(0.0, maxX);
    final y = pos.dy.clamp(0.0, (screen.height - 56).clamp(0.0, screen.height));
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pos = _clampToScreen(_pos ?? _defaultPosition(screen), screen);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: _DragHandle(
        onDrag: (delta) {
          final next = _clampToScreen(pos + delta, screen);
          setState(() => _pos = next);
        },
        onDragEnd: () => _savePosition(_pos ?? pos),
        child: DebugLogOverlay(
          width: widget.width,
          maxVisibleLines: widget.maxVisibleLines,
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.child,
    required this.onDrag,
    required this.onDragEnd,
  });

  final Widget child;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    // We capture pan gestures on the whole panel; this makes it easy to reposition.
    // The user can move it away, then interact with the UI underneath.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => onDrag(d.delta),
      onPanEnd: (_) => onDragEnd(),
      child: child,
    );
  }
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
