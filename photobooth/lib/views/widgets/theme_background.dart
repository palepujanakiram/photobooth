import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../utils/app_config.dart';
import 'cached_network_image.dart';

/// Full-screen background used on Select Theme and Generate Photo screens.
/// Blurred theme sample image, theme color overlay, gradient, and falling dots.
class ThemeBackground extends StatelessWidget {
  const ThemeBackground({super.key, this.theme});

  final ThemeModel? theme;

  static String _themeSampleImageUrl(ThemeModel? theme) {
    if (theme?.sampleImageUrl == null || theme!.sampleImageUrl!.isEmpty) {
      return '';
    }
    final imageUrl = theme.sampleImageUrl!;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
    return '$baseUrl$path';
  }

  static Color? _parseThemeBackgroundColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _themeSampleImageUrl(theme);
    final themeColor =
        theme != null ? _parseThemeBackgroundColor(theme!.backgroundColor) : null;

    return Stack(
      key: ValueKey(theme?.id ?? 'no-theme'),
      fit: StackFit.expand,
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            key: ValueKey(imageUrl),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
                    ),
                  ),
                ),
                errorWidget: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (themeColor != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.35),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: imageUrl.isNotEmpty
                    ? [
                        const Color(0xFF0D2130).withValues(alpha: 0.75),
                        const Color(0xFF0A1628).withValues(alpha: 0.82),
                        const Color(0xFF050810).withValues(alpha: 0.88),
                      ]
                    : const [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: _FallingDotsBackground(),
        ),
      ],
    );
  }
}

class _FallingDotsBackground extends StatefulWidget {
  const _FallingDotsBackground();

  @override
  State<_FallingDotsBackground> createState() => _FallingDotsBackgroundState();
}

class _FallingDotsBackgroundState extends State<_FallingDotsBackground>
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
          painter: _FallingStarfieldPainter(progress: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _FallingStarfieldPainter extends CustomPainter {
  _FallingStarfieldPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = _SeededRandom(42);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 120; i++) {
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

  @override
  bool shouldRepaint(covariant _FallingStarfieldPainter old) =>
      old.progress != progress;
}

class _SeededRandom {
  _SeededRandom(int seed)
      : _state = BigInt.from(seed) & _mask;

  BigInt _state;

  static final BigInt _a = BigInt.parse('6364136223846793005');
  static final BigInt _c = BigInt.parse('1442695040888963407');
  static final BigInt _mask = BigInt.parse('9223372036854775807'); // 0x7fffffffffffffff

  double nextDouble() {
    _state = (_a * _state + _c) & _mask;
    return _state.toDouble() / _mask.toDouble();
  }
}
