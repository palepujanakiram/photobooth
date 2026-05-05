import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-screen overlay: drifting star dots plus a single occasional shooting-star streak
/// (random direction each pass, short fast sweep, sparse timing).
class FallingStarfieldBackground extends StatefulWidget {
  const FallingStarfieldBackground({super.key});

  @override
  State<FallingStarfieldBackground> createState() =>
      _FallingStarfieldBackgroundState();
}

class _FallingStarfieldBackgroundState extends State<FallingStarfieldBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  final math.Random _rng = math.Random();

  /// Travel direction (radians), refreshed when the animation loop wraps.
  double _meteorAngleRad = 0.7;

  /// Lateral offset along the perpendicular axis, normalized ~[-0.5, 0.5].
  double _lateralNorm = 0;

  /// Shifts when in the 25s loop the meteor appears ([0,1)).
  double _phase = 0;

  double _prevProgress = 0;

  /// Fraction of each loop where the meteor is visible (rest = idle). Smaller = faster crossing.
  static const double _visibleFraction = 0.018;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _meteorAngleRad = _rng.nextDouble() * 2 * math.pi;
    _lateralNorm = _rng.nextDouble() - 0.5;
    _phase = _rng.nextDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
    _controller.addListener(_onTick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  void _onTick() {
    final v = _controller.value;
    if (v < _prevProgress) {
      setState(() {
        _meteorAngleRad = _rng.nextDouble() * 2 * math.pi;
        _lateralNorm = _rng.nextDouble() - 0.5;
        _phase = _rng.nextDouble();
      });
    }
    _prevProgress = v;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _StarfieldPainter(
              progress: _controller.value,
              meteorAngleRad: _meteorAngleRad,
              lateralNorm: _lateralNorm,
              phase: _phase,
              visibleFraction: _visibleFraction,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.progress,
    required this.meteorAngleRad,
    required this.lateralNorm,
    required this.phase,
    required this.visibleFraction,
  });

  final double progress;
  final double meteorAngleRad;
  final double lateralNorm;
  final double phase;
  final double visibleFraction;

  static const int _dotCount = 60;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFallingDots(canvas, size);
    _paintShootingStar(canvas, size);
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

  void _paintShootingStar(Canvas canvas, Size size) {
    final p = (progress + phase) % 1.0;
    if (p >= visibleFraction) return;

    final t = (p / visibleFraction).clamp(0.0, 1.0);
    final rnd = _SeededRandom(9001);
    final ux = math.cos(meteorAngleRad);
    final uy = math.sin(meteorAngleRad);
    final px = -uy;
    final py = ux;

    final short = math.min(size.width, size.height);
    final travel = math.max(size.width, size.height) * 1.75;
    final lateral = lateralNorm * short * 0.55;

    final cx = size.width / 2 + px * lateral;
    final cy = size.height / 2 + py * lateral;

    final headX = cx + ux * travel * (t - 0.5);
    final headY = cy + uy * travel * (t - 0.5);
    final head = Offset(headX, headY);

    final tailLen =
        (44 + rnd.nextDouble() * 40) * (short / 420).clamp(0.7, 1.25);
    final tail = Offset(headX - ux * tailLen, headY - uy * tailLen);

    final glowPaint = Paint()
      ..color = const Color(0xFFB8E0FF).withValues(alpha: 0.09)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawLine(tail, head, glowPaint);

    final corePaint = Paint()
      ..shader = ui.Gradient.linear(
        tail,
        head,
        [
          Colors.white.withValues(alpha: 0.0),
          const Color(0xFF7EC8FF).withValues(alpha: 0.28),
          const Color(0xFFE8F4FF).withValues(alpha: 0.75),
          Colors.white.withValues(alpha: 0.88),
        ],
        const [0.0, 0.38, 0.78, 1.0],
      )
      ..strokeWidth = 1.4 + rnd.nextDouble() * 0.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tail, head, corePaint);

    canvas.drawCircle(
      head,
      1.6,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.progress != progress ||
      old.meteorAngleRad != meteorAngleRad ||
      old.lateralNorm != lateralNorm ||
      old.phase != phase ||
      old.visibleFraction != visibleFraction;
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
