import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../utils/app_config.dart';
import '../../views/widgets/cached_network_image.dart';
import 'theme_model.dart';

/// Full-screen theme preview so users can appreciate details before selecting.
class ThemePreviewScreen extends StatelessWidget {
  const ThemePreviewScreen({
    super.key,
    required this.theme,
    required this.imageUrl,
    required this.onSelect,
  });

  final ThemeModel theme;
  final String imageUrl;
  final VoidCallback onSelect;

  static String resolveSampleImageUrl(ThemeModel theme) {
    final raw = theme.sampleImageUrl?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$baseUrl$path';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final maxCardWidth = isLandscape ? 520.0 : 460.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: Opacity(
                  opacity: 0.45,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: (mq.size.width * 0.8).round().clamp(640, 1400),
                    cacheHeight: (mq.size.height * 0.8).round().clamp(360, 1400),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: 'Close',
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxCardWidth),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                    tag: 'theme-preview-${theme.id}',
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: AspectRatio(
                                        aspectRatio: 9 / 16,
                                        child: imageUrl.isEmpty
                                            ? const ColoredBox(color: Color(0xFF111111))
                                            : CachedNetworkImage(
                                                imageUrl: imageUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                                cacheWidth: 900,
                                                cacheHeight: 1600,
                                                placeholder: const ColoredBox(
                                                  color: Color(0xFF111111),
                                                  child: Center(
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    theme.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      height: 1.12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (theme.description.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      theme.description.trim(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.78),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => Navigator.of(context).maybePop(),
                                child: const Text(
                                  'Back',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2A6DF4),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: onSelect,
                                child: const Text(
                                  'Select this theme',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

