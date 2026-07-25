import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';

/// Single 2×6 strip preview (4 stacked shots) with a live look filter.
class FotoFlashbackStripPreview extends StatelessWidget {
  const FotoFlashbackStripPreview({
    super.key,
    required this.imageDataUrls,
    required this.filterId,
    this.width = defaultStripWidth,
    this.height = defaultStripHeight,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final double width;
  final double height;

  /// 2×6 strip proportions (width : height ≈ 1 : 3).
  static const double defaultStripWidth = 132;
  static const double defaultStripHeight = 396;
  static const double aspectRatio = defaultStripWidth / defaultStripHeight;

  @override
  Widget build(BuildContext context) {
    final images =
        imageDataUrls.take(kStripShotCount).map(_bytesFromDataUrl).toList();
    return ColorFiltered(
      colorFilter: stripPreviewColorFilter(filterId),
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all((width * 0.06).clamp(6.0, 10.0)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            for (var i = 0; i < kStripShotCount; i++) ...[
              if (i > 0) SizedBox(height: (height * 0.01).clamp(3.0, 5.0)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: images.length > i
                      ? Image.memory(
                          images[i],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          gaplessPlayback: true,
                        )
                      : const ColoredBox(color: Colors.black12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Approximate zenai sharp grades for live Flutter preview.
///
/// Ids match [kStripFilterIds] / `GET /api/strip/filters`. Server compose is
/// the source of truth; these matrices only hint the look while tapping.
ColorFilter stripPreviewColorFilter(String filterId) {
  switch (filterId) {
    case 'classic_warm':
      // Vintage amber matte
      return const ColorFilter.matrix(<double>[
        1.05, 0.05, 0, 0, 8,
        0.02, 0.95, 0, 0, 4,
        0, 0.02, 0.88, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'peach_glow':
      // Soft peach skin glow (Life4Cuts-style)
      return const ColorFilter.matrix(<double>[
        1.1, 0.08, 0.04, 0, 14,
        0.06, 0.98, 0.04, 0, 8,
        0.04, 0.06, 0.9, 0, 6,
        0, 0, 0, 1, 0,
      ]);
    case 'soft_film':
      // Dreamy low-contrast
      return const ColorFilter.matrix(<double>[
        0.95, 0.05, 0, 0, 10,
        0.05, 0.95, 0, 0, 10,
        0, 0.05, 0.95, 0, 10,
        0, 0, 0, 1, 0,
      ]);
    case 'candy_pop':
      // Bright playful pop
      return const ColorFilter.matrix(<double>[
        1.15, 0.05, 0, 0, 0,
        0, 1.05, 0.05, 0, 0,
        0.05, 0, 1.2, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'golden_hour':
      // Honey sunset warmth
      return const ColorFilter.matrix(<double>[
        1.14, 0.1, 0.02, 0, 12,
        0.06, 0.96, 0.02, 0, 6,
        0, 0.04, 0.78, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'cool_mint':
      // Fresh teal-cool studio
      return const ColorFilter.matrix(<double>[
        0.88, 0.04, 0.06, 0, 2,
        0.04, 1.06, 0.08, 0, 6,
        0.06, 0.1, 1.12, 0, 8,
        0, 0, 0, 1, 0,
      ]);
    case 'gloss_pop':
      // Punchy Y2K contrast
      return const ColorFilter.matrix(<double>[
        1.2, 0.02, 0.06, 0, -6,
        0, 1.12, 0.08, 0, -4,
        0.08, 0, 1.24, 0, -2,
        0, 0, 0, 1, 0,
      ]);
    case 'mono':
      // Noir B&W
      return const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'clean':
    default:
      return const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ]);
  }
}

Uint8List _bytesFromDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
  return base64Decode(b64);
}
