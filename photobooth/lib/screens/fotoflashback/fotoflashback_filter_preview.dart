import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';
import 'fotoflashback_sheet_layout_view_widgets.dart';
import 'fotoflashback_strip_chrome_view_widgets.dart';

/// Single 2×6 strip preview (one cut of the dual print sheet), or a 4×6 sheet
/// layout preview when [frameId] is polaroid / grid_2x2 / romantic / plain_6x4.
///
/// Dual-strip chrome: print hands off two identical strips on a 4×6 sheet; the
/// look UI shows one strip so guests edit the piece they keep. Sheet layouts
/// preview the full 4×6 arrangement. Credential bar matches zenai watermark.
class FotoFlashbackStripPreview extends StatelessWidget {
  const FotoFlashbackStripPreview({
    super.key,
    required this.imageDataUrls,
    required this.filterId,
    this.frameId = kDefaultStripFrameId,
    this.frameOverlayUrl,
    this.frameCaption,
    this.stickerId = kDefaultStripStickerId,
    this.placements = const [],
    this.scribbles = const [],
    this.drawMode = false,
    this.imagesAreGraded = false,
    this.layout,
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

  /// Admin scrapbook template overlay (https PNG) for live preview.
  final String? frameOverlayUrl;
  final String? frameCaption;

  /// When true, [imageDataUrls] are already Sharp-graded — skip ColorFilter.
  final bool imagesAreGraded;

  /// Shared print geometry from `GET /api/strip/filters` → `layout`.
  final StripWysiwygLayout? layout;

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

  /// Classic 1-shot landscape 6×4 (1800×1200).
  static const double single6x4AspectRatio = 1800 / 1200;

  /// Classic 1-shot portrait 4×6 (1200×1800).
  static const double single4x6AspectRatio = 1200 / 1800;

  /// One 2×6 strip (half sheet width).
  static const double defaultStripWidth = defaultSheetWidth / 2;
  static const double defaultStripHeight = defaultSheetHeight;
  static const double stripAspectRatio =
      defaultStripWidth / defaultStripHeight;

  /// Layout uses the single-strip aspect guests edit.
  static const double aspectRatio = stripAspectRatio;

  /// Matches zenai `STRIP_PRINT.border / stripWidth` (4 / 600).
  static const double printBorderRatio = 4 / 600;

  /// Compact credential burned onto Classic strips (not AI — brand only).
  static const String credentialLine = 'FOTOZEN AI';

  @override
  Widget build(BuildContext context) {
    final wysiwyg = layout ?? StripWysiwygLayout.defaults;
    if (imageDataUrls.length == 1) {
      return _Single6x4Preview(
        imageDataUrl: imageDataUrls.first,
        filterId: filterId,
        frameId: frameId,
        imagesAreGraded: imagesAreGraded,
        placements: placements,
        scribbles: scribbles,
        drawMode: drawMode,
        width: width,
        height: height,
        onMovePlacement: onMovePlacement,
        onRemovePlacement: onRemovePlacement,
        onScribbleStart: onScribbleStart,
        onScribbleUpdate: onScribbleUpdate,
        onScribbleEnd: onScribbleEnd,
      );
    }
    if (isStripSheetLayout(frameId)) {
      // Glyph ref = half sheet width so icons match dual-strip booth size (print uses 600 on 1200).
      final glyphRefWidth = width / 2;
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FotoFlashbackSheetLayoutPreview(
              imageDataUrls: imageDataUrls,
              colorFilter: imagesAreGraded
                  ? null
                  : stripPreviewColorFilter(filterId),
              layoutId: frameId,
              layout: wysiwyg,
              width: width,
              height: height,
            ),
            // Stickers / scribbles in sheet-normalized 0–1 space (matches print).
            if (placements.isNotEmpty)
              for (final p in placements)
                _PlacementSticker(
                  placement: p,
                  stripWidth: width,
                  stripHeight: height,
                  glyphRefWidth: glyphRefWidth,
                  layout: wysiwyg,
                  absorbPointers: drawMode,
                  onMove: onMovePlacement,
                  onRemove: onRemovePlacement,
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
            if (drawMode)
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

    // Compact watermark math from zenai `watermark.ts` (one-strip column).
    final fontSize = (width / wysiwyg.watermarkFontDivisor).clamp(
      wysiwyg.watermarkFontMin,
      wysiwyg.watermarkFontMax,
    );
    final credentialBarH = fontSize * wysiwyg.watermarkBarHeightFactor;
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
            frameOverlayUrl: frameOverlayUrl,
            frameCaption: frameCaption,
            stickerId: stickerId,
            imagesAreGraded: imagesAreGraded,
            layout: wysiwyg,
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
                child: Text(
                  credentialLine,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.6,
                    height: 1.05,
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
    this.frameOverlayUrl,
    this.frameCaption,
    this.imagesAreGraded = false,
    this.layout,
    this.onMovePlacement,
    this.onRemovePlacement,
    this.onScribbleStart,
    this.onScribbleUpdate,
    this.onScribbleEnd,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final String frameId;
  final String? frameOverlayUrl;
  final String? frameCaption;
  final String stickerId;
  final List<StripStickerPlacement> placements;
  final List<StripScribbleStroke> scribbles;
  final bool drawMode;
  final bool interactive;
  final bool imagesAreGraded;
  final StripWysiwygLayout? layout;
  final double width;
  final double height;
  final void Function(String id, double x, double y)? onMovePlacement;
  final void Function(String id)? onRemovePlacement;
  final void Function(double x, double y)? onScribbleStart;
  final void Function(double x, double y)? onScribbleUpdate;
  final VoidCallback? onScribbleEnd;

  @override
  Widget build(BuildContext context) {
    final wysiwyg = layout ?? StripWysiwygLayout.defaults;
    final images =
        imageDataUrls.take(kStripShotCount).map(_bytesFromDataUrl).toList();
    final chrome = StripChromeLook.forFrame(
      frameId,
      borderRatio: wysiwyg.borderRatio,
      accentStrokeRatio: wysiwyg.accentStrokeRatio,
      noirAccentStrokeRatio: wysiwyg.noirAccentStrokeRatio,
    );
    final pad = width * chrome.borderRatio;
    // Filmstrip print uses contain so faces aren't cropped into the rails.
    final photoFit =
        chrome.showFilmstripSprockets ? BoxFit.contain : BoxFit.cover;
    final photoColumn = Column(
      children: [
        for (var i = 0; i < kStripShotCount; i++)
          Expanded(
            child: images.length > i
                ? ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                      images[i],
                      fit: photoFit,
                      width: double.infinity,
                      height: double.infinity,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  )
                : const ColoredBox(color: Colors.black12),
          ),
      ],
    );

    return Container(
      key: ValueKey<String>('strip_chrome_$frameId'),
      width: width,
      height: height,
      color: chrome.fill,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Padding(
            padding: EdgeInsets.all(pad),
            child: imagesAreGraded
                ? photoColumn
                : ColorFiltered(
                    colorFilter: stripPreviewColorFilter(filterId),
                    child: photoColumn,
                  ),
          ),
          StripChromeOverlay(
            look: chrome,
            width: width,
            height: height,
            borderPad: pad,
          ),
          if (frameOverlayUrl != null && frameOverlayUrl!.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.network(
                  frameOverlayUrl!,
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (frameCaption != null && frameCaption!.trim().isNotEmpty)
            Positioned(
              left: width * 0.08,
              bottom: height * 0.025,
              child: IgnorePointer(
                child: Text(
                  '${frameCaption!.trim()}  ♥',
                  style: TextStyle(
                    color: const Color(0xFF111111),
                    fontSize: width * 0.055,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
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
                layout: wysiwyg,
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
    this.glyphRefWidth,
    this.layout,
    this.absorbPointers = false,
    this.onMove,
    this.onRemove,
  });

  final StripStickerPlacement placement;
  final double stripWidth;
  final double stripHeight;
  /// When set (sheet layouts), size icons from this width instead of [stripWidth].
  final double? glyphRefWidth;
  final StripWysiwygLayout? layout;
  final bool absorbPointers;
  final void Function(String id, double x, double y)? onMove;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context) {
    final size = _glyphSize(
      placement,
      glyphRefWidth ?? stripWidth,
      layout ?? StripWysiwygLayout.defaults,
    );
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

double _glyphSize(
  StripStickerPlacement p,
  double stripWidth,
  StripWysiwygLayout layout,
) {
  final ratio = switch (p.type) {
    'confetti' => layout.stickerLargeRatio,
    _ => layout.stickerBaseRatio,
  };
  // Match zenai placementGlyphSize — min only, no preview max clamp.
  final size = stripWidth * ratio * p.scale;
  return size < layout.stickerMinPx ? layout.stickerMinPx : size;
}

Widget _glyph(StripStickerPlacement p, double size) {
  switch (p.type) {
    case 'sparkles':
      // Drawn path — ✦ often missing on Flutter web fonts.
      return _SparkleGlyph(size: size, color: const Color(0xFFFFD54A));
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
    case 'flowers':
      return Text(
        '❀',
        style: TextStyle(
          color: const Color(0xFFFF6B9D).withValues(alpha: 0.95),
          fontSize: size,
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
  if (!isStripSheetLayout(frameId)) {
    return StripChromeLook.forFrame(frameId).fill;
  }
  switch (frameId) {
    case 'polaroid':
      return Colors.white;
    case 'grid_2x2':
      return const Color(0xFFFFFAF5);
    case 'romantic':
      return Colors.white;
    default:
      return Colors.white;
  }
}

Color? stripPreviewFrameAccent(String frameId) {
  if (!isStripSheetLayout(frameId)) {
    return StripChromeLook.forFrame(frameId).accent;
  }
  switch (frameId) {
    case 'polaroid':
      return const Color(0xFF8A6A55);
    case 'grid_2x2':
      return const Color(0xFF2C1810);
    case 'romantic':
      return const Color(0xFFE8919A);
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
        _stickerSparkle(width * 0.08, height * 0.04, width * 0.14,
            const Color(0xFFFFD54A)),
        _stickerSparkle(width * 0.75, height * 0.4, width * 0.12,
            const Color(0xFFFFC107)),
        _stickerSparkle(width * 0.18, height * 0.85, width * 0.1,
            const Color(0xFFFFD54A)),
      ];
    case 'confetti':
      return [
        _stickerSparkle(width * 0.15, height * 0.08, width * 0.1,
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
    case 'flowers':
      return [
        _stickerText('❀', width * 0.14, height * 0.08, width * 0.14,
            const Color(0xFFFF6B9D)),
        _stickerText('❀', width * 0.72, height * 0.38, width * 0.12,
            const Color(0xFFFF6B9D)),
        _stickerText('❀', width * 0.16, height * 0.72, width * 0.13,
            const Color(0xFFFF6B9D)),
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

Widget _stickerSparkle(double left, double top, double size, Color color) {
  return Positioned(
    left: left,
    top: top,
    child: _SparkleGlyph(size: size, color: color),
  );
}

/// Eight-point sparkle drawn with paths (font-independent for web).
class _SparkleGlyph extends StatelessWidget {
  const _SparkleGlyph({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SparklePainter(color: color.withValues(alpha: 0.96)),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.color});

  final Color color;

  static Path _fourPoint(double cx, double cy, double r, double waist) {
    return Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + waist, cy - waist)
      ..lineTo(cx + r, cy)
      ..lineTo(cx + waist, cy + waist)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - waist, cy + waist)
      ..lineTo(cx - r, cy)
      ..lineTo(cx - waist, cy - waist)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.shortestSide / 2;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Long cardinal arms + shorter arms rotated 45° (classic ✦ shape).
    canvas.drawPath(_fourPoint(cx, cy, r, r * 0.14), fill);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(0.785398163); // pi/4
    canvas.translate(-cx, -cy);
    canvas.drawPath(_fourPoint(cx, cy, r * 0.58, r * 0.1), fill);
    canvas.restore();
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.12,
      Paint()..color = const Color(0xFFFFF59D).withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) {
    return oldDelegate.color != color;
  }
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

/// Landscape Classic 1-shot preview (matches zenai composeSingle6x4).
class _Single6x4Preview extends StatelessWidget {
  const _Single6x4Preview({
    required this.imageDataUrl,
    required this.filterId,
    required this.frameId,
    required this.imagesAreGraded,
    required this.placements,
    required this.scribbles,
    required this.drawMode,
    required this.width,
    required this.height,
    this.onMovePlacement,
    this.onRemovePlacement,
    this.onScribbleStart,
    this.onScribbleUpdate,
    this.onScribbleEnd,
  });

  final String imageDataUrl;
  final String filterId;
  final String frameId;
  final bool imagesAreGraded;
  final List<StripStickerPlacement> placements;
  final List<StripScribbleStroke> scribbles;
  final bool drawMode;
  final double width;
  final double height;
  final void Function(String id, double x, double y)? onMovePlacement;
  final void Function(String id)? onRemovePlacement;
  final void Function(double x, double y)? onScribbleStart;
  final void Function(double x, double y)? onScribbleUpdate;
  final VoidCallback? onScribbleEnd;

  Color get _matte {
    if (frameId == 'noir') return const Color(0xFF111111);
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytesFromDataUrl(imageDataUrl);
    final margin = width * 0.027; // ~48/1800
    final photo = Image.memory(
      bytes,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
    final photoLayer = imagesAreGraded
        ? photo
        : ColorFiltered(
            colorFilter: stripPreviewColorFilter(filterId),
            child: photo,
          );

    return Container(
      key: ValueKey<String>('single6x4_$frameId'),
      width: width,
      height: height,
      color: _matte,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(margin),
            child: ColoredBox(
              color: _matte,
              child: photoLayer,
            ),
          ),
          if (frameId == 'filmstrip')
            CustomPaint(
              painter: _SingleFilmstripSprocketPainter(margin: margin),
            ),
          if (placements.isNotEmpty)
            for (final p in placements)
              _PlacementSticker(
                placement: p,
                stripWidth: width,
                stripHeight: height,
                glyphRefWidth: width * 0.35,
                layout: StripWysiwygLayout.defaults,
                absorbPointers: drawMode,
                onMove: onMovePlacement,
                onRemove: onRemovePlacement,
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
          if (drawMode)
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

class _SingleFilmstripSprocketPainter extends CustomPainter {
  _SingleFilmstripSprocketPainter({required this.margin});

  final double margin;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()..color = const Color(0xFF1A1A1A);
    final hole = Paint()..color = Colors.white;
    final railW = margin.clamp(8.0, 28.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, railW, size.height), rail);
    canvas.drawRect(
      Rect.fromLTWH(size.width - railW, 0, railW, size.height),
      rail,
    );
    final holeSize = railW * 0.45;
    final step = holeSize * 2.2;
    for (var y = holeSize; y < size.height - holeSize; y += step) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(railW / 2, y),
            width: holeSize,
            height: holeSize * 0.7,
          ),
          const Radius.circular(2),
        ),
        hole,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width - railW / 2, y),
            width: holeSize,
            height: holeSize * 0.7,
          ),
          const Radius.circular(2),
        ),
        hole,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SingleFilmstripSprocketPainter oldDelegate) =>
      oldDelegate.margin != margin;
}
