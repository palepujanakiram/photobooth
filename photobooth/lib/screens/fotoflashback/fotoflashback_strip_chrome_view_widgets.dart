import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dual-strip chrome for Classic / Doodle / Party / Cinema / Noir previews.
class StripChromeLook {
  const StripChromeLook({
    required this.fill,
    required this.borderRatio,
    this.accent,
    this.accentWidthFactor = 0.0,
    this.secondaryAccent,
    this.showNoirDoubleLine = false,
    this.creativeStyle,
    this.footerCaption,
  });

  final Color fill;
  final double borderRatio;
  final Color? accent;
  final double accentWidthFactor;
  final Color? secondaryAccent;
  final bool showNoirDoubleLine;

  /// When set, [StripChromeOverlay] paints scrapbook doodles instead of a rim.
  final String? creativeStyle;
  final String? footerCaption;

  /// Print uses a 4px pad on a 600-wide strip for every chrome frame.
  static const double printBorderRatio = 4 / 600;
  static const double printAccentStrokeRatio = 1.75 / 600;
  static const double printNoirAccentStrokeRatio = 2.5 / 600;

  static StripChromeLook forFrame(
    String frameId, {
    double? borderRatio,
    double? accentStrokeRatio,
    double? noirAccentStrokeRatio,
  }) {
    final border = borderRatio ?? printBorderRatio;
    final noirAccent = noirAccentStrokeRatio ?? printNoirAccentStrokeRatio;
    switch (frameId) {
      case 'doodle':
      case 'ticket': // legacy Sky
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
          creativeStyle: 'doodle',
          footerCaption: 'Date night',
        );
      case 'party':
      case 'blush': // legacy Blush
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
          creativeStyle: 'party',
          footerCaption: 'Party vibes',
        );
      case 'cinema':
      case 'gold': // legacy Gold
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
          creativeStyle: 'cinema',
          footerCaption: 'Lights, camera',
        );
      case 'noir':
        return StripChromeLook(
          fill: const Color(0xFF121216),
          borderRatio: border,
          accent: const Color(0xFFC8C8D0),
          accentWidthFactor: noirAccent,
          secondaryAccent: const Color(0xFF6E6E78),
          showNoirDoubleLine: true,
        );
      case 'classic':
      default:
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
        );
    }
  }
}

/// Thin accent rim, Noir double line, or creative doodle stamps.
class StripChromeOverlay extends StatelessWidget {
  const StripChromeOverlay({
    super.key,
    required this.look,
    required this.width,
    required this.height,
    required this.borderPad,
  });

  final StripChromeLook look;
  final double width;
  final double height;
  final double borderPad;

  @override
  Widget build(BuildContext context) {
    final creative = look.creativeStyle;
    if (creative != null) {
      return IgnorePointer(
        child: CustomPaint(
          size: Size(width, height),
          painter: _CreativeDoodlePainter(
            style: creative,
            footerCaption: look.footerCaption ?? '',
          ),
        ),
      );
    }

    final accent = look.accent;
    if (accent == null) return const SizedBox.shrink();

    final accentW = (width * look.accentWidthFactor).clamp(0.5, 4.0);
    final noirInset = width * (5 / 600);
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.all(borderPad),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: accent, width: accentW),
          ),
          child: look.showNoirDoubleLine && look.secondaryAccent != null
              ? Padding(
                  padding: EdgeInsets.all(noirInset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: look.secondaryAccent!,
                        width: (width * (1.5 / 600)).clamp(0.5, 2.0),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _CreativeDoodlePainter extends CustomPainter {
  _CreativeDoodlePainter({
    required this.style,
    required this.footerCaption,
  });

  final String style;
  final String footerCaption;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width * 0.0035)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = const Color(0xFF111111);

    const border = 4.0;
    final cellH = (size.height - border * 2) / 4;
    for (var i = 0; i < 4; i++) {
      final top = border + i * cellH;
      _paintCellOrnaments(
        canvas,
        size,
        stroke,
        fill,
        cellIndex: i,
        top: top,
        cellH: cellH,
      );
    }

    if (footerCaption.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '$footerCaption  ♥',
        style: TextStyle(
          color: const Color(0xFF111111),
          fontSize: size.width * 0.048,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.7);
    tp.paint(
      canvas,
      Offset(size.width * 0.06, size.height - size.height * 0.048),
    );
  }

  void _paintCellOrnaments(
    Canvas canvas,
    Size size,
    Paint stroke,
    Paint fill, {
    required int cellIndex,
    required double top,
    required double cellH,
  }) {
    final left = size.width * 0.04;
    final right = size.width * 0.96;
    final topY = top + cellH * 0.08;
    final botY = top + cellH * 0.88;
    final midY = top + cellH * 0.5;

    void star(double cx, double cy, double r) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4;
        final rad = i.isEven ? r : r * 0.35;
        final x = cx + math.cos(a) * rad;
        final y = cy + math.sin(a) * rad;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, stroke);
    }

    void sun(double cx, double cy, double r) {
      canvas.drawCircle(Offset(cx, cy), r, stroke);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(
          Offset(cx + math.cos(a) * (r + 2), cy + math.sin(a) * (r + 2)),
          Offset(cx + math.cos(a) * (r + 8), cy + math.sin(a) * (r + 8)),
          stroke,
        );
      }
    }

    void squiggle(double x, double y, double w) {
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + w * 0.25, y - 5, x + w * 0.5, y)
        ..quadraticBezierTo(x + w * 0.75, y + 5, x + w, y);
      canvas.drawPath(path, stroke);
    }

    if (style == 'doodle') {
      switch (cellIndex) {
        case 0:
          squiggle(left, topY, size.width * 0.14);
          squiggle(left, topY + 10, size.width * 0.1);
          sun(right - 10, topY + 4, size.width * 0.025);
          break;
        case 1:
          _bow(canvas, stroke, fill, left + 12, topY + 4, size.width * 0.03);
          break;
        case 2:
          star(left + 10, topY, size.width * 0.02);
          star(left + 24, topY + 12, size.width * 0.015);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                size.width * 0.03,
                top + cellH * 0.05,
                size.width * 0.94,
                cellH * 0.9,
              ),
              const Radius.circular(4),
            ),
            Paint()
              ..color = const Color(0xFF111111)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2.0, size.width * 0.005)
              ..strokeJoin = StrokeJoin.round,
          );
          break;
        default:
          star(left + 10, topY, size.width * 0.018);
          _bow(canvas, stroke, fill, right - 16, botY - 8, size.width * 0.025);
      }
      return;
    }

    if (style == 'party') {
      star(left + 10, topY, size.width * 0.022);
      if (cellIndex.isEven) {
        _bow(canvas, stroke, fill, right - 14, topY + 2, size.width * 0.028);
      } else {
        sun(right - 12, botY - 6, size.width * 0.022);
      }
      return;
    }

    // cinema
    star(left + 12, topY, size.width * 0.02);
    if (cellIndex == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.04,
            top + cellH * 0.06,
            size.width * 0.92,
            cellH * 0.88,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = const Color(0xFF111111)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, size.width * 0.005)
          ..strokeJoin = StrokeJoin.round,
      );
    } else if (cellIndex == 0 || cellIndex == 2) {
      final cx = right - 18;
      final cy = midY;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: size.width * 0.06,
          height: size.width * 0.035,
        ),
        stroke,
      );
    }
  }

  void _bow(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    double cx,
    double cy,
    double s,
  ) {
    final left = Path()
      ..moveTo(cx - s, cy)
      ..quadraticBezierTo(cx - s * 0.4, cy - s * 0.7, cx, cy)
      ..quadraticBezierTo(cx - s * 0.4, cy + s * 0.7, cx - s, cy);
    final right = Path()
      ..moveTo(cx + s, cy)
      ..quadraticBezierTo(cx + s * 0.4, cy - s * 0.7, cx, cy)
      ..quadraticBezierTo(cx + s * 0.4, cy + s * 0.7, cx + s, cy);
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);
    canvas.drawCircle(Offset(cx, cy), s * 0.22, fill);
  }

  @override
  bool shouldRepaint(covariant _CreativeDoodlePainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.footerCaption != footerCaption;
}
