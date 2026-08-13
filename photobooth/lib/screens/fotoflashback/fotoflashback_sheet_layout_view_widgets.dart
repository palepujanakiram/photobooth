import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';

/// On-screen 4×6 preview for Classic sheet layouts (polaroid / grid / romantic).
///
/// Geometry comes from zenai `STRIP_WYSIWYG_LAYOUT`. When [colorFilter] is null,
/// [imageDataUrls] are assumed already Sharp-graded (Option A).
class FotoFlashbackSheetLayoutPreview extends StatelessWidget {
  const FotoFlashbackSheetLayoutPreview({
    super.key,
    required this.imageDataUrls,
    required this.layoutId,
    required this.width,
    required this.height,
    this.colorFilter,
    this.layout,
  });

  final List<String> imageDataUrls;
  final ColorFilter? colorFilter;
  final String layoutId;
  final StripWysiwygLayout? layout;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final wysiwyg = layout ?? StripWysiwygLayout.defaults;
    final images =
        imageDataUrls.take(kStripShotCount).map(_bytesFromDataUrl).toList();
    final body = switch (layoutId) {
      'polaroid' => _PolaroidSheetPreview(
          images: images,
          layout: wysiwyg,
          colorFilter: colorFilter,
        ),
      'romantic' => _RomanticSheetPreview(
          images: images,
          layout: wysiwyg,
          colorFilter: colorFilter,
        ),
      _ => _Grid2x2SheetPreview(
          images: images,
          layout: wysiwyg,
          colorFilter: colorFilter,
        ),
    };

    return SizedBox(
      key: ValueKey<String>('sheet_layout_$layoutId'),
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Grade photos only — chrome/copy stay unfiltered (matches print).
          body,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SheetCredentialBar(layout: wysiwyg, sheetWidth: width),
          ),
        ],
      ),
    );
  }
}

class _SheetCredentialBar extends StatelessWidget {
  const _SheetCredentialBar({
    required this.layout,
    required this.sheetWidth,
  });

  final StripWysiwygLayout layout;
  final double sheetWidth;

  @override
  Widget build(BuildContext context) {
    final fontSize = (sheetWidth / layout.watermarkFontDivisor).clamp(
      layout.watermarkFontMin,
      layout.watermarkFontMax,
    );
    final barH = fontSize * layout.watermarkBarHeightFactor;
    return IgnorePointer(
      child: Container(
        height: barH,
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.42),
        child: Text(
          'FOTOZEN AI',
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
    );
  }
}

Widget _gradedPhoto({
  required Uint8List? bytes,
  required ColorFilter? colorFilter,
  BoxFit fit = BoxFit.cover,
}) {
  if (bytes == null) return const ColoredBox(color: Colors.black12);
  final image = Image.memory(
    bytes,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
  if (colorFilter == null) return image;
  return ColorFiltered(colorFilter: colorFilter, child: image);
}

class _PolaroidSheetPreview extends StatelessWidget {
  const _PolaroidSheetPreview({
    required this.images,
    required this.layout,
    this.colorFilter,
  });

  final List<Uint8List> images;
  final StripWysiwygLayout layout;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cellW = w * layout.polaroidFrameW;
        final cellH = h * layout.polaroidFrameH;

        return ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: w * layout.polaroidSlots[i].left,
                  top: h * layout.polaroidSlots[i].top,
                  child: Transform.rotate(
                    angle: layout.polaroidSlots[i].rotDeg * math.pi / 180,
                    child: _PolaroidCell(
                      bytes: images.length > i ? images[i] : null,
                      width: cellW,
                      height: cellH,
                      colorFilter: colorFilter,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PolaroidCell extends StatelessWidget {
  const _PolaroidCell({
    required this.bytes,
    required this.width,
    required this.height,
    this.colorFilter,
  });

  final Uint8List? bytes;
  final double width;
  final double height;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    final pad = width * (22 / 464);
    final caption = height * (70 / 612);
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(pad, pad, pad, caption),
      color: const Color(0xFFFFFCF8),
      child: _gradedPhoto(bytes: bytes, colorFilter: colorFilter),
    );
  }
}

class _Grid2x2SheetPreview extends StatelessWidget {
  const _Grid2x2SheetPreview({
    required this.images,
    required this.layout,
    this.colorFilter,
  });

  final List<Uint8List> images;
  final StripWysiwygLayout layout;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final headerH = h * layout.gridHeaderH;
        final footerH = h * layout.gridFooterH;
        final margin = w * layout.gridMargin;
        final gap = w * layout.gridGap;
        final gridH = h - headerH - footerH - margin;
        final cellW = (w - margin * 2 - gap) / 2;
        final cellH = (gridH - gap) / 2;

        Widget cell(int i) {
          return SizedBox(
            width: cellW,
            height: cellH,
            child: _gradedPhoto(
              bytes: images.length > i ? images[i] : null,
              colorFilter: colorFilter,
              fit: BoxFit.contain,
            ),
          );
        }

        return ColoredBox(
          color: Colors.white,
          child: Column(
            children: [
              SizedBox(
                height: headerH,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          layout.gridTitle,
                          style: TextStyle(
                            color: const Color(0xFF2C1810),
                            fontSize: (w * 0.075).clamp(10.0, 20.0),
                            fontFamily: 'serif',
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          layout.gridSubtitle,
                          style: TextStyle(
                            color: const Color(0xFF6B4F3A),
                            fontSize: (w * 0.038).clamp(8.0, 12.0),
                            fontFamily: 'serif',
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(margin, 0, margin, margin),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          cell(0),
                          SizedBox(width: gap),
                          cell(1),
                        ],
                      ),
                      SizedBox(height: gap),
                      Row(
                        children: [
                          cell(2),
                          SizedBox(width: gap),
                          cell(3),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: footerH),
            ],
          ),
        );
      },
    );
  }
}

class _RomanticSheetPreview extends StatelessWidget {
  const _RomanticSheetPreview({
    required this.images,
    required this.layout,
    this.colorFilter,
  });

  final List<Uint8List> images;
  final StripWysiwygLayout layout;
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        Widget photo(int i) {
          final slot = layout.romanticSlots[i];
          return Positioned(
            left: w * slot.left,
            top: h * slot.top,
            width: w * slot.width,
            height: h * slot.height,
            child: _gradedPhoto(
              bytes: images.length > i ? images[i] : null,
              colorFilter: colorFilter,
              fit: BoxFit.contain,
            ),
          );
        }

        return ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: h * layout.romanticHeartY - (w * layout.romanticHeartFont),
                child: Text(
                  '♥',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFE8919A),
                    fontSize: w * layout.romanticHeartFont,
                    height: 1,
                  ),
                ),
              ),
              photo(0),
              photo(1),
              photo(2),
              photo(3),
              Positioned(
                left: w * 0.04,
                right: w * 0.04,
                top: h * layout.romanticCaptionY -
                    (w * layout.romanticCaptionFont),
                child: Text(
                  layout.romanticCaption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFC45C74),
                    fontSize: w * layout.romanticCaptionFont,
                    fontStyle: FontStyle.italic,
                    fontFamily: 'cursive',
                    fontFamilyFallback: const [
                      'Brush Script MT',
                      'Segoe Script',
                      'Apple Chancery',
                      'serif',
                    ],
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Uint8List _bytesFromDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
  return base64Decode(b64);
}
