import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../utils/app_config.dart';
import 'cached_network_image.dart';
import 'falling_starfield_background.dart';

/// Full-screen background used on Select Theme and Generate Photo screens.
/// Blurred theme sample image, theme color overlay, gradient, and animated starfield.
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
          child: FallingStarfieldBackground(),
        ),
      ],
    );
  }
}
