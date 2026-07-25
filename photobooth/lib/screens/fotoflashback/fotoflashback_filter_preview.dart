import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';

/// Single 2×6 strip preview (one cut of the dual print sheet).
///
/// Print still hands off two identical strips on a 4×6 sheet; the look UI shows
/// one strip so guests edit the piece they keep. Credential bar matches zenai
/// per-strip watermark (stacked "AI GENERATED" / "FotoZen AI").
class FotoFlashbackStripPreview extends StatelessWidget {
  const FotoFlashbackStripPreview({
    super.key,
    required this.imageDataUrls,
    required this.filterId,
    this.frameId = kDefaultStripFrameId,
    this.stickerId = kDefaultStripStickerId,
    this.placements = const [],
    this.scribbles = const [],
    this.drawMode = false,
    this.onMovePlacement,
    this.onRemovePlacement,
    this.onScribbleStart,
    this.onScribbleUpdate,
    this.onScribbleEnd,
    this.width = defaultStripWidth,
    this.height = defaultStripHeight,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final String frameId;

  /// Legacy pack id (used only when [placements] is empty).
  final String stickerId;
  final List<StripStickerPlacement> placements;
  final List<StripScribbleStroke> scribbles;
  final bool drawMode;
  final void Function(String id, double x, double y)? onMovePlacement;
  final void Function(String id)? onRemovePlacement;
  final void Function(double x, double y)? onScribbleStart;
  final void Function(double x, double y)? onScribbleUpdate;
  final VoidCallback? onScribbleEnd;

  /// Single strip size (matches zenai 600×1800 / 2"×6").
  final double width;
  final double height;

  /// Print sheet 1200×1800 (4"×6" dual strip) — staff / compose reference.
  static const double defaultSheetWidth = 264;
  static const double defaultSheetHeight = 396;
  static const double sheetAspectRatio =
      defaultSheetWidth / defaultSheetHeight;

  /// One 2×6 strip (half sheet width).
  static const double defaultStripWidth = defaultSheetWidth / 2;
  static const double defaultStripHeight = defaultSheetHeight;
  static const double stripAspectRatio =
      defaultStripWidth / defaultStripHeight;

  /// Layout uses the single-strip aspect guests edit.
  static const double aspectRatio = stripAspectRatio;

  /// Matches zenai `STRIP_PRINT.border / stripWidth` (4 / 600).
  static const double printBorderRatio = 4 / 600;

  /// Stacked credential copy burned onto each cut strip at print time.
  static const String credentialLine1 = 'AI GENERATED';
  static const String credentialLine2 = 'FotoZen AI';

  @override
  Widget build(BuildContext context) {
    // Matches zenai compact per-strip watermark (stacked lines on ~600px strip).
    final fontSize = (width / 42).clamp(7.0, 11.0);
    final credentialBarH = (fontSize * 2.6).clamp(18.0, 28.0);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _FotoFlashbackSingleStrip(
            imageDataUrls: imageDataUrls,
            filterId: filterId,
            frameId: frameId,
            stickerId: stickerId,
            placements: placements,
            scribbles: scribbles,
            drawMode: drawMode,
            interactive: true,
            onMovePlacement: onMovePlacement,
            onRemovePlacement: onRemovePlacement,
            onScribbleStart: onScribbleStart,
            onScribbleUpdate: onScribbleUpdate,
            onScribbleEnd: onScribbleEnd,
            width: width,
            height: height,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: credentialBarH,
                alignment: Alignment.center,
                color: Colors.black.withValues(alpha: 0.42),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      credentialLine1,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      credentialLine2,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FotoFlashbackSingleStrip extends StatelessWidget {
  const _FotoFlashbackSingleStrip({
    required this.imageDataUrls,
    required this.filterId,
    required this.frameId,
    required this.stickerId,
    required this.placements,
    required this.scribbles,
    required this.drawMode,
    required this.interactive,
    required this.width,
    required this.height,
    this.onMovePlacement,
    this.onRemovePlacement,
    this.onScribbleStart,
    this.onScribbleUpdate,
    this.onScribbleEnd,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final String frameId;
  final String stickerId;
  final List<StripStickerPlacement> placements;
  final List<StripScribbleStroke> scribbles;
  final bool drawMode;
  final bool interactive;
  final double width;
  final double height;
  final void Function(String id, double x, double y)? onMovePlacement;
  final void Function(String id)? onRemovePlacement;
  final void Function(double x, double y)? onScribbleStart;
  final void Function(double x, double y)? onScribbleUpdate;
  final VoidCallback? onScribbleEnd;

  @override
  Widget build(BuildContext context) {
    final images =
        imageDataUrls.take(kStripShotCount).map(_bytesFromDataUrl).toList();
    final pad = width * FotoFlashbackStripPreview.printBorderRatio;
    final frameColor = stripPreviewFrameColor(frameId);
    final accent = stripPreviewFrameAccent(frameId);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: frameColor,
        border: accent == null ? null : Border.all(color: accent, width: 1),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Padding(
            padding: EdgeInsets.all(pad),
            child: ColorFiltered(
              colorFilter: stripPreviewColorFilter(filterId),
              child: Column(
                children: [
                  for (var i = 0; i < kStripShotCount; i++)
                    Expanded(
                      child: images.length > i
                          ? Image.memory(
                              images[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            )
                          : const ColoredBox(color: Colors.black12),
                    ),
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
                absorbPointers: !interactive || drawMode,
                onMove: interactive ? onMovePlacement : null,
                onRemove: interactive ? onRemovePlacement : null,
              ),
          if (scribbles.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScribblePainter(
                    strokes: scribbles,
                    stripWidth: width,
                    stripHeight: height,
                  ),
                ),
              ),
            ),
          if (drawMode && interactive)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  if (onScribbleStart == null) return;
                  onScribbleStart!(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                    (details.localPosition.dy / height).clamp(0.0, 1.0),
                  );
                },
                onPanUpdate: (details) {
                  if (onScribbleUpdate == null) return;
                  onScribbleUpdate!(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                    (details.localPosition.dy / height).clamp(0.0, 1.0),
                  );
                },
                onPanEnd: (_) => onScribbleEnd?.call(),
                onPanCancel: onScribbleEnd,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScribblePainter extends CustomPainter {
  _ScribblePainter({
    required this.strokes,
    required this.stripWidth,
    required this.stripHeight,
  });

  final List<StripScribbleStroke> strokes;
  final double stripWidth;
  final double stripHeight;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = _colorFromHex(stroke.color)
        ..strokeWidth = (stroke.width * stripWidth).clamp(1.5, 14.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(
          stroke.points.first.x * stripWidth,
          stroke.points.first.y * stripHeight,
        );
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
          stroke.points[i].x * stripWidth,
          stroke.points[i].y * stripHeight,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScribblePainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.stripWidth != stripWidth ||
        oldDelegate.stripHeight != stripHeight;
  }
}

Color _colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  if (cleaned.length != 6) return Colors.white;
  return Color(int.parse('FF$cleaned', radix: 16));
}

class _PlacementSticker extends StatelessWidget {
  const _PlacementSticker({
    required this.placement,
    required this.stripWidth,
    required this.stripHeight,
    this.absorbPointers = false,
    this.onMove,
    this.onRemove,
  });

  final StripStickerPlacement placement;
  final double stripWidth;
  final double stripHeight;
  final bool absorbPointers;
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
      child: IgnorePointer(
        ignoring: absorbPointers,
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
      ),
    );
  }
}

double _glyphSize(StripStickerPlacement p, double stripWidth) {
  final base = switch (p.type) {
    'confetti' || 'butterflies' || 'petals' => stripWidth * 0.2,
    _ => stripWidth * 0.16,
  };
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
    case 'confetti':
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: size * 0.05,
              top: size * 0.15,
              child: Transform.rotate(
                angle: -0.35,
                child: Container(
                  width: size * 0.35,
                  height: size * 0.2,
                  color: const Color(0xFFFF6B8A),
                ),
              ),
            ),
            Positioned(
              right: size * 0.05,
              top: size * 0.05,
              child: Transform.rotate(
                angle: 0.4,
                child: Container(
                  width: size * 0.3,
                  height: size * 0.18,
                  color: const Color(0xFFFFD166),
                ),
              ),
            ),
            Positioned(
              left: size * 0.2,
              bottom: size * 0.1,
              child: Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: const BoxDecoration(
                  color: Color(0xFF6EC6FF),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: size * 0.12,
              bottom: size * 0.2,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: size * 0.28,
                  height: size * 0.18,
                  color: const Color(0xFFB388FF),
                ),
              ),
            ),
          ],
        ),
      );
    case 'stars':
      return Text(
        '★',
        style: TextStyle(
          color: const Color(0xFFFFD54A).withValues(alpha: 0.95),
          fontSize: size,
          height: 1,
        ),
      );
    case 'bows':
      return Text(
        '✿',
        style: TextStyle(
          color: const Color(0xFFFF8FB8).withValues(alpha: 0.95),
          fontSize: size,
          height: 1,
        ),
      );
    case 'flowers':
      return Text(
        '❀',
        style: TextStyle(
          color: const Color(0xFFFF6B9D).withValues(alpha: 0.95),
          fontSize: size,
          height: 1,
        ),
      );
    case 'butterflies':
      return Text(
        '🦋',
        style: TextStyle(
          fontSize: size * 0.9,
          height: 1,
        ),
      );
    case 'petals':
      return Text(
        '💮',
        style: TextStyle(
          fontSize: size * 0.85,
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
    case 'confetti':
      return [
        _stickerText('✦', width * 0.15, height * 0.08, width * 0.1,
            const Color(0xFFFF6B8A)),
        _stickerText('●', width * 0.75, height * 0.35, width * 0.08,
            const Color(0xFFFFD166)),
        _stickerText('■', width * 0.2, height * 0.6, width * 0.08,
            const Color(0xFF6EC6FF)),
        _stickerText('●', width * 0.78, height * 0.82, width * 0.07,
            const Color(0xFFB388FF)),
      ];
    case 'stars':
      return [
        _stickerText('★', width * 0.12, height * 0.08, width * 0.14,
            const Color(0xFFFFD54A)),
        _stickerText('★', width * 0.72, height * 0.4, width * 0.12,
            const Color(0xFFFFD54A)),
        _stickerText('★', width * 0.18, height * 0.78, width * 0.11,
            const Color(0xFFFFD54A)),
      ];
    case 'bows':
      return [
        _stickerText('✿', width * 0.7, height * 0.08, width * 0.14,
            const Color(0xFFFF8FB8)),
        _stickerText('✿', width * 0.1, height * 0.42, width * 0.12,
            const Color(0xFFFF8FB8)),
        _stickerText('✿', width * 0.72, height * 0.75, width * 0.13,
            const Color(0xFFFF8FB8)),
      ];
    case 'flowers':
      return [
        _stickerText('❀', width * 0.14, height * 0.08, width * 0.14,
            const Color(0xFFFF6B9D)),
        _stickerText('❀', width * 0.72, height * 0.38, width * 0.12,
            const Color(0xFFFF6B9D)),
        _stickerText('❀', width * 0.16, height * 0.72, width * 0.13,
            const Color(0xFFFF6B9D)),
      ];
    case 'butterflies':
      return [
        _stickerText('🦋', width * 0.16, height * 0.1, width * 0.14,
            const Color(0xFFC9A0FF)),
        _stickerText('🦋', width * 0.7, height * 0.42, width * 0.12,
            const Color(0xFFFF9EC8)),
        _stickerText('🦋', width * 0.18, height * 0.76, width * 0.13,
            const Color(0xFFA78BFA)),
      ];
    case 'petals':
      return [
        _stickerText('💮', width * 0.14, height * 0.12, width * 0.13,
            const Color(0xFFFFB3C6)),
        _stickerText('💮', width * 0.72, height * 0.4, width * 0.12,
            const Color(0xFFFF8FAB)),
        _stickerText('💮', width * 0.18, height * 0.74, width * 0.12,
            const Color(0xFFFFC2D1)),
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
