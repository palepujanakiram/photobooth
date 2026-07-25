import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';

/// Single 2×6 strip preview with live look + frame + sticker overlays.
class FotoFlashbackStripPreview extends StatelessWidget {
  const FotoFlashbackStripPreview({
    super.key,
    required this.imageDataUrls,
    required this.filterId,
    this.frameId = kDefaultStripFrameId,
    this.stickerId = kDefaultStripStickerId,
    this.placements = const [],
    this.onMovePlacement,
    this.onRemovePlacement,
    this.width = defaultStripWidth,
    this.height = defaultStripHeight,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final String frameId;

  /// Legacy pack id (used only when [placements] is empty).
  final String stickerId;
  final List<StripStickerPlacement> placements;
  final void Function(String id, double x, double y)? onMovePlacement;
  final void Function(String id)? onRemovePlacement;
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
    final pad = (width * 0.06).clamp(6.0, 10.0);
    final frameColor = stripPreviewFrameColor(frameId);
    final accent = stripPreviewFrameAccent(frameId);
    final showBrandBar = frameId != 'classic';

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: frameColor,
        borderRadius: BorderRadius.circular(4),
        border: accent == null ? null : Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.all(pad),
            child: ColorFiltered(
              colorFilter: stripPreviewColorFilter(filterId),
              child: Column(
                children: [
                  for (var i = 0; i < kStripShotCount; i++) ...[
                    if (i > 0)
                      SizedBox(height: (height * 0.01).clamp(3.0, 5.0)),
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
          ),
          if (placements.isEmpty)
            ..._stickerOverlays(stickerId, width, height)
          else
            for (final p in placements)
              _PlacementSticker(
                placement: p,
                stripWidth: width,
                stripHeight: height,
                onMove: onMovePlacement,
                onRemove: onRemovePlacement,
              ),
          if (showBrandBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: (height * 0.07).clamp(18.0, 28.0),
                  alignment: Alignment.center,
                  color: frameId == 'blush'
                      ? Colors.white.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.35),
                  child: Text(
                    'FOTOFLASHBACK',
                    style: TextStyle(
                      color: frameId == 'blush'
                          ? const Color(0xFF7A3D48)
                          : const Color(0xFFD8D0C8),
                      fontSize: (width * 0.07).clamp(7.0, 10.0),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
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

class _PlacementSticker extends StatelessWidget {
  const _PlacementSticker({
    required this.placement,
    required this.stripWidth,
    required this.stripHeight,
    this.onMove,
    this.onRemove,
  });

  final StripStickerPlacement placement;
  final double stripWidth;
  final double stripHeight;
  final void Function(String id, double x, double y)? onMove;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) {
    final size = _glyphSize(placement, stripWidth);
    final left = (placement.x * stripWidth) - size / 2;
    final top = (placement.y * stripHeight) - size / 2;
    final child = _glyph(placement, size);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onMove == null
            ? null
            : (details) {
                final nx = ((placement.x * stripWidth) + details.delta.dx) /
                    stripWidth;
                final ny = ((placement.y * stripHeight) + details.delta.dy) /
                    stripHeight;
                onMove!(placement.id, nx, ny);
              },
        onDoubleTap: onRemove == null ? null : () => onRemove!(placement.id),
        child: child,
      ),
    );
  }
}

double _glyphSize(StripStickerPlacement p, double stripWidth) {
  final base = p.type == 'date' ? stripWidth * 0.2 : stripWidth * 0.16;
  return (base * p.scale).clamp(14.0, 56.0);
}

Widget _glyph(StripStickerPlacement p, double size) {
  switch (p.type) {
    case 'sparkles':
      return Text(
        '✦',
        style: TextStyle(
          color: const Color(0xFFFFF7D6).withValues(alpha: 0.95),
          fontSize: size,
          height: 1,
          shadows: const [
            Shadow(color: Color(0x99F5D76E), blurRadius: 2),
          ],
        ),
      );
    case 'date':
      return Text(
        _previewDateStamp(),
        style: TextStyle(
          color: const Color(0xFF6B5B4F).withValues(alpha: 0.95),
          fontSize: (size * 0.55).clamp(8.0, 14.0),
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
    case 'hearts':
    default:
      return Text(
        '♥',
        style: TextStyle(
          color: const Color(0xFFFF6B8A).withValues(alpha: 0.92),
          fontSize: size,
          height: 1,
        ),
      );
  }
}

Color stripPreviewFrameColor(String frameId) {
  switch (frameId) {
    case 'ticket':
      return const Color(0xFF1C1816);
    case 'blush':
      return const Color(0xFFFFE4E8);
    case 'noir':
      return const Color(0xFF202022);
    case 'classic':
    default:
      return Colors.white;
  }
}

Color? stripPreviewFrameAccent(String frameId) {
  switch (frameId) {
    case 'ticket':
      return const Color(0xFFC4A574);
    case 'blush':
      return const Color(0xFFE8919A);
    case 'noir':
      return const Color(0xFFA0A0A8);
    default:
      return null;
  }
}

List<Widget> _stickerOverlays(String stickerId, double width, double height) {
  switch (stickerId) {
    case 'hearts':
      return [
        _stickerText('♥', width * 0.72, height * 0.03, width * 0.16,
            const Color(0xFFFF6B8A)),
        _stickerText('♥', width * 0.08, height * 0.28, width * 0.12,
            const Color(0xFFFF6B8A)),
        _stickerText('♥', width * 0.68, height * 0.52, width * 0.13,
            const Color(0xFFFF6B8A)),
        _stickerText('♥', width * 0.1, height * 0.74, width * 0.11,
            const Color(0xFFFF6B8A)),
      ];
    case 'sparkles':
      return [
        _stickerText('✦', width * 0.08, height * 0.04, width * 0.14,
            const Color(0xFFFFF7D6)),
        _stickerText('✦', width * 0.75, height * 0.4, width * 0.12,
            const Color(0xFFFFE8A3)),
        _stickerText('✧', width * 0.18, height * 0.85, width * 0.1,
            const Color(0xFFFFF7D6)),
      ];
    case 'date':
      return [
        Positioned(
          left: 0,
          right: 0,
          bottom: height * 0.035,
          child: Text(
            _previewDateStamp(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF6B5B4F).withValues(alpha: 0.9),
              fontSize: (width * 0.08).clamp(8.0, 11.0),
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    case 'none':
    default:
      return const [];
  }
}

Widget _stickerText(
  String text,
  double left,
  double top,
  double size,
  Color color,
) {
  return Positioned(
    left: left,
    top: top,
    child: Text(
      text,
      style: TextStyle(
        color: color.withValues(alpha: 0.9),
        fontSize: size,
        height: 1,
      ),
    ),
  );
}

String _previewDateStamp() {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final now = DateTime.now();
  return '${months[now.month - 1]} ${now.day}, ${now.year}';
}

/// Approximate zenai Sharp grades for live Flutter preview.
ColorFilter stripPreviewColorFilter(String filterId) {
  switch (filterId) {
    case 'classic_warm':
      return const ColorFilter.matrix(<double>[
        1.05, 0.05, 0, 0, 8,
        0.02, 0.95, 0, 0, 4,
        0, 0.02, 0.88, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'peach_glow':
      return const ColorFilter.matrix(<double>[
        1.1, 0.08, 0.04, 0, 14,
        0.06, 0.98, 0.04, 0, 8,
        0.04, 0.06, 0.9, 0, 6,
        0, 0, 0, 1, 0,
      ]);
    case 'soft_film':
      return const ColorFilter.matrix(<double>[
        0.95, 0.05, 0, 0, 10,
        0.05, 0.95, 0, 0, 10,
        0, 0.05, 0.95, 0, 10,
        0, 0, 0, 1, 0,
      ]);
    case 'candy_pop':
      return const ColorFilter.matrix(<double>[
        1.15, 0.05, 0, 0, 0,
        0, 1.05, 0.05, 0, 0,
        0.05, 0, 1.2, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'golden_hour':
      return const ColorFilter.matrix(<double>[
        1.14, 0.1, 0.02, 0, 12,
        0.06, 0.96, 0.02, 0, 6,
        0, 0.04, 0.78, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case 'cool_mint':
      return const ColorFilter.matrix(<double>[
        0.88, 0.04, 0.06, 0, 2,
        0.04, 1.06, 0.08, 0, 6,
        0.06, 0.1, 1.12, 0, 8,
        0, 0, 0, 1, 0,
      ]);
    case 'gloss_pop':
      return const ColorFilter.matrix(<double>[
        1.2, 0.02, 0.06, 0, -6,
        0, 1.12, 0.08, 0, -4,
        0.08, 0, 1.24, 0, -2,
        0, 0, 0, 1, 0,
      ]);
    case 'mono':
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
