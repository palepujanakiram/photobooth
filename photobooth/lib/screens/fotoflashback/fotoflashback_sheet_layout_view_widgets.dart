import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/strip_models.dart';

/// On-screen 4×6 preview for Classic sheet layouts (polaroid / grid / film / romantic).
///
/// Print compose still happens on zenai; this mirrors the arrangement so guests
/// see a clear difference vs dual-strip chrome frames.
class FotoFlashbackSheetLayoutPreview extends StatelessWidget {
  const FotoFlashbackSheetLayoutPreview({
    super.key,
    required this.imageDataUrls,
    required this.colorFilter,
    required this.layoutId,
    required this.width,
    required this.height,
  });

  final List<String> imageDataUrls;
  final ColorFilter colorFilter;
  final String layoutId;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final images =
        imageDataUrls.take(kStripShotCount).map(_bytesFromDataUrl).toList();
    final filtered = ColorFiltered(
      colorFilter: colorFilter,
      child: switch (layoutId) {
        'polaroid' => _PolaroidSheetPreview(images: images),
        'filmstrip' => _FilmstripSheetPreview(images: images),
        'romantic' => _RomanticSheetPreview(images: images),
        _ => _Grid2x2SheetPreview(images: images),
      },
    );

    return SizedBox(
      key: ValueKey<String>('sheet_layout_$layoutId'),
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          filtered,
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SheetCredentialBar(),
          ),
        ],
      ),
    );
  }
}

class _SheetCredentialBar extends StatelessWidget {
  const _SheetCredentialBar();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 22,
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.42),
        child: const Text(
          'FOTOZEN AI',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            height: 1.05,
          ),
        ),
      ),
    );
  }
}

class _PolaroidSheetPreview extends StatelessWidget {
  const _PolaroidSheetPreview({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final slots = <({double l, double t, double rot})>[
          (l: 0.06, t: 0.07, rot: -0.07),
          (l: 0.52, t: 0.05, rot: 0.05),
          (l: 0.08, t: 0.52, rot: 0.04),
          (l: 0.50, t: 0.50, rot: -0.05),
        ];
        final cellW = w * 0.40;
        final cellH = h * 0.38;

        return ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: w * slots[i].l,
                  top: h * slots[i].t,
                  child: Transform.rotate(
                    angle: slots[i].rot,
                    child: _PolaroidCell(
                      bytes: images.length > i ? images[i] : null,
                      width: cellW,
                      height: cellH,
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
  });

  final Uint8List? bytes;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pad = width * 0.06;
    final caption = height * 0.14;
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(pad, pad, pad, caption),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: bytes == null
          ? const ColoredBox(color: Colors.black12)
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

class _Grid2x2SheetPreview extends StatelessWidget {
  const _Grid2x2SheetPreview({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final headerH = h * 0.12;
        final margin = w * 0.04;
        final gap = w * 0.025;
        final gridH = h - headerH - margin;
        final cellW = (w - margin * 2 - gap) / 2;
        final cellH = (gridH - gap) / 2;

        Widget cell(int i) {
          final bytes = images.length > i ? images[i] : null;
          return SizedBox(
            width: cellW,
            height: cellH,
            child: bytes == null
                ? const ColoredBox(color: Colors.black12)
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Together',
                      style: TextStyle(
                        color: const Color(0xFF2C1810),
                        fontSize: (w * 0.075).clamp(12.0, 20.0),
                        fontFamily: 'serif',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Our favorite moments',
                      style: TextStyle(
                        color: const Color(0xFF6B4F3A),
                        fontSize: (w * 0.038).clamp(9.0, 12.0),
                        fontFamily: 'serif',
                      ),
                    ),
                  ],
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
            ],
          ),
        );
      },
    );
  }
}

class _FilmstripSheetPreview extends StatelessWidget {
  const _FilmstripSheetPreview({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Match dual-strip cell aspect; contain-on-black so faces aren't cropped.
        final labelGutter = w * 0.14;
        final marginY = h * 0.045;
        final gutter = h * 0.01;
        final cellH = (h - marginY * 2 - gutter * 3) / 4;
        const dualCellAspect = (600 - 8) / (1800 / 4); // ~1.32
        final photoW = cellH * dualCellAspect;
        final railW = (photoW * 0.12).clamp(8.0, 18.0);
        final stripW = photoW + railW * 2;
        final stripLeft = labelGutter;
        final photoLeft = stripLeft + railW;
        final holeW = (railW * 0.55).clamp(4.0, 10.0);
        final holeH = (holeW * 1.35).clamp(6.0, 14.0);
        final holePitch = holeH * 1.75;
        final holeCount =
            ((h * 0.90) / holePitch).floor().clamp(8, 28);

        return ColoredBox(
          color: Colors.white,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: stripLeft,
                top: h * 0.02,
                width: stripW,
                height: h * 0.96,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0A),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              for (var i = 0; i < holeCount; i++) ...[
                Positioned(
                  left: stripLeft + (railW - holeW) / 2,
                  top: h * 0.04 + i * holePitch,
                  child: _SprocketHole(width: holeW, height: holeH),
                ),
                Positioned(
                  left: stripLeft + stripW - railW + (railW - holeW) / 2,
                  top: h * 0.04 + i * holePitch,
                  child: _SprocketHole(width: holeW, height: holeH),
                ),
              ],
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: labelGutter,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'MEMORIES',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: const Color(0xFF1A1A1A),
                        fontSize: (w * 0.07).clamp(12.0, 18.0),
                        letterSpacing: 3.5,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: photoLeft,
                  top: marginY + i * (cellH + gutter),
                  width: photoW,
                  height: cellH,
                  child: ColoredBox(
                    color: Colors.black,
                    child: images.length > i
                        ? Image.memory(
                            images[i],
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          )
                        : const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Classic film perforation — solid white hole on black stock.
class _SprocketHole extends StatelessWidget {
  const _SprocketHole({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.28),
      ),
    );
  }
}

class _RomanticSheetPreview extends StatelessWidget {
  const _RomanticSheetPreview({required this.images});

  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        Widget photo(int i, double left, double top, double pw, double ph) {
          final bytes = images.length > i ? images[i] : null;
          return Positioned(
            left: left,
            top: top,
            width: pw,
            height: ph,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: bytes == null
                  ? const ColoredBox(color: Colors.black12)
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
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
                top: h * 0.015,
                child: Text(
                  '♥',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFE8919A),
                    fontSize: (w * 0.12).clamp(18.0, 28.0),
                    height: 1,
                  ),
                ),
              ),
              photo(0, w * 0.06, h * 0.10, w * 0.43, h * 0.36),
              photo(1, w * 0.51, h * 0.13, w * 0.43, h * 0.36),
              photo(2, w * 0.10, h * 0.50, w * 0.30, h * 0.26),
              photo(3, w * 0.58, h * 0.52, w * 0.30, h * 0.26),
              // Sit above the compact FotoZen watermark / credential bar.
              Positioned(
                left: w * 0.04,
                right: w * 0.04,
                bottom: h * 0.10,
                child: Text(
                  'Forever starts here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFC45C74),
                    fontSize: (w * 0.065).clamp(13.0, 18.0),
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
