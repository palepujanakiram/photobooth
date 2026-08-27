import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dual-strip chrome for Classic / Noir / Filmstrip previews.
class StripChromeLook {
  const StripChromeLook({
    required this.fill,
    required this.borderRatio,
    this.accent,
    this.accentWidthFactor = 0.0,
    this.secondaryAccent,
    this.showNoirDoubleLine = false,
    this.showFilmstripSprockets = false,
  });

  final Color fill;
  final double borderRatio;
  final Color? accent;
  final double accentWidthFactor;
  final Color? secondaryAccent;
  final bool showNoirDoubleLine;
  final bool showFilmstripSprockets;

  /// Print uses a 10px pad on a 600-wide strip for Classic / Noir (HAMA-style).
  static const double printBorderRatio = 10 / 600;
  static const double printAccentStrokeRatio = 1.75 / 600;
  static const double printNoirAccentStrokeRatio = 2.5 / 600;

  /// Matches zenai `FILMSTRIP_DUAL` on a 600×1800 strip.
  static const double filmRailRatio = 36 / 600;
  static const double filmHoleWRatio = 18 / 600;
  static const double filmHoleHRatio = 24 / 1800;
  static const double filmHolePitchRatio = 46 / 1800;
  static const double filmHoleStartYRatio = 28 / 1800;
  /// Matches zenai `FILMSTRIP_DUAL.holeInset` (pull punches toward photo).
  static const double filmHoleInsetRatio = 4 / 600;

  static StripChromeLook forFrame(
    String frameId, {
    double? borderRatio,
    double? accentStrokeRatio,
    double? noirAccentStrokeRatio,
  }) {
    final border = borderRatio ?? printBorderRatio;
    final noirAccent = noirAccentStrokeRatio ?? printNoirAccentStrokeRatio;
    switch (frameId) {
      case 'noir':
        return StripChromeLook(
          fill: const Color(0xFF121216),
          borderRatio: border,
          accent: const Color(0xFFC8C8D0),
          accentWidthFactor: noirAccent,
          secondaryAccent: const Color(0xFF6E6E78),
          showNoirDoubleLine: true,
        );
      case 'filmstrip':
        // Rail width matches zenai FILMSTRIP_DUAL.railW (36 on 600-wide strip).
        return const StripChromeLook(
          fill: Color(0xFF0A0A0A),
          borderRatio: filmRailRatio,
          showFilmstripSprockets: true,
        );
      case 'classic':
      default:
        // Legacy Sky/Blush/Gold and removed doodle frames fall through here.
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
        );
    }
  }
}

/// Thin accent rim, Noir double line, or Filmstrip sprocket punches.
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
    if (look.showFilmstripSprockets) {
      return _FilmstripSprocketOverlay(
        width: width,
        height: height,
        railPad: borderPad,
      );
    }

    final accent = look.accent;
    if (accent == null || look.accentWidthFactor <= 0) {
      return const SizedBox.shrink();
    }

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

/// White sprocket punches on the left/right film rails (preview parity with print).
class _FilmstripSprocketOverlay extends StatelessWidget {
  const _FilmstripSprocketOverlay({
    required this.width,
    required this.height,
    required this.railPad,
  });

  final double width;
  final double height;
  final double railPad;

  @override
  Widget build(BuildContext context) {
    final holeW = width * StripChromeLook.filmHoleWRatio;
    final holeH = height * StripChromeLook.filmHoleHRatio;
    final pitch = height * StripChromeLook.filmHolePitchRatio;
    final startY = height * StripChromeLook.filmHoleStartYRatio;
    final inset = width * StripChromeLook.filmHoleInsetRatio;
    final leftHoleX = (railPad - holeW) / 2 + inset;
    final rightHoleX = width - railPad + (railPad - holeW) / 2 - inset;
    final holes = <Widget>[];
    for (var y = startY; y + holeH < height - (height * (24 / 1800)); y += pitch) {
      holes.add(
        Positioned(
          left: leftHoleX,
          top: y,
          child: _SprocketHole(width: holeW, height: holeH),
        ),
      );
      holes.add(
        Positioned(
          left: rightHoleX,
          top: y,
          child: _SprocketHole(width: holeW, height: holeH),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(clipBehavior: Clip.hardEdge, children: holes),
    );
  }
}

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
        borderRadius: BorderRadius.circular(math.min(width, height) / 2),
      ),
    );
  }
}
