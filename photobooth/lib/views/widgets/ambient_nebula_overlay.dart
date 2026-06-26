import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Slow drifting nebula glow for generation wait screens.
class AmbientNebulaOverlay extends StatefulWidget {
  const AmbientNebulaOverlay({super.key});

  @override
  State<AmbientNebulaOverlay> createState() => _AmbientNebulaOverlayState();
}

class _AmbientNebulaOverlayState extends State<AmbientNebulaOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * math.pi * 2;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  math.sin(t) * 0.35,
                  math.cos(t * 0.7) * 0.25,
                ),
                radius: 1.2,
                colors: [
                  const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    math.cos(t * 0.8) * 0.4,
                    math.sin(t * 0.6) * 0.3,
                  ),
                  radius: 1.0,
                  colors: [
                    const Color(0xFF3B82F6).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
