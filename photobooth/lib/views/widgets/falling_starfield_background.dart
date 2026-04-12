import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-screen overlay: drifting star dots plus diagonal shooting-star streaks.
class FallingStarfieldBackground extends StatefulWidget {
  const FallingStarfieldBackground({super.key});

  @override
  State<FallingStarfieldBackground> createState() =>
      _FallingStarfieldBackgroundState();
}

class _FallingStarfieldBackgroundState extends State<FallingStarfieldBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _StarfieldPainter(progress: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.progress});

  final double progress;

  static const int _dotCount = 120;
  static const int _meteorCount = 4;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFallingDots(canvas, size);
    _paintShootingStars(canvas, size);
  }

  void _paintFallingDots(Canvas canvas, Size size) {
    final rnd = _SeededRandom(42);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < _dotCount; i++) {
      final x = rnd.nextDouble() * size.width;
      final baseY = rnd.nextDouble();
      final pixelY =
          ((baseY + progress) * (size.height + 100)) % (size.height + 100);
      if (pixelY >= 0 && pixelY <= size.height) {
        final r = 1.0 + rnd.nextDouble();
        canvas.drawCircle(Offset(x, pixelY), r, paint);
      }
    }
  }

  void _paintShootingStars(Canvas canvas, Size size) {
    for (int i = 0; i < _meteorCount; i++) {
      _paintOneShootingStar(canvas, size, i);
    }
  }

  void _paintOneShootingStar(Canvas canvas, Size size, int index) {
    final rnd = _SeededRandom(9001 + index * 131);
    final phase = rnd.nextDouble();
    final speed = 0.55 + rnd.nextDouble() * 0.65;
    final t = (progress * speed + phase) % 1.0;

    // Diagonal trail: upper-left → lower-right with per-star variation ("trailblaze").
    final startX = (-0.18 - rnd.nextDouble() * 0.12) * size.width;
    final startY = (-0.12 - rnd.nextDouble() * 0.18) * size.height;
    final endX = (1.06 + rnd.nextDouble() * 0.14) * size.width;
    final endY = (1.04 + rnd.nextDouble() * 0.12) * size.height;
    final dx = endX - startX;
    final dy = endY - startY;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;

    final headX = startX + dx * t;
    final headY = startY + dy * t;
    final head = Offset(headX, headY);

    final short = math.min(size.width, size.height);
    final tailLen =
        (48 + rnd.nextDouble() * 72) * (short / 420).clamp(0.75, 1.35);
    final tail = Offset(headX - ux * tailLen, headY - uy * tailLen);

    // Soft outer glow (wider, faint).
    final glowPaint = Paint()
      ..color = const Color(0xFFB8E0FF).withValues(alpha: 0.14)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(tail, head, glowPaint);

    final corePaint = Paint()
      ..shader = ui.Gradient.linear(
        tail,
        head,
        [
          Colors.white.withValues(alpha: 0.0),
          const Color(0xFF7EC8FF).withValues(alpha: 0.35),
          const Color(0xFFE8F4FF).withValues(alpha: 0.9),
          Colors.white.withValues(alpha: 1.0),
        ],
        const [0.0, 0.38, 0.78, 1.0],
      )
      ..strokeWidth = 1.6 + rnd.nextDouble() * 0.9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tail, head, corePaint);

    canvas.drawCircle(
      head,
      1.9,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.progress != progress;
}

class _SeededRandom {
  _SeededRandom(int seed) : _state = BigInt.from(seed) & _mask;

  BigInt _state;

  static final BigInt _a = BigInt.parse('6364136223846793005');
  static final BigInt _c = BigInt.parse('1442695040888963407');
  static final BigInt _mask = BigInt.parse('9223372036854775807');

  double nextDouble() {
    _state = (_a * _state + _c) & _mask;
    return _state.toDouble() / _mask.toDouble();
  }
}
