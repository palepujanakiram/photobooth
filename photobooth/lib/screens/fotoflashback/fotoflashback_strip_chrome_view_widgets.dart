import 'package:flutter/material.dart';

/// Dual-strip chrome for Classic / Noir previews.
class StripChromeLook {
  const StripChromeLook({
    required this.fill,
    required this.borderRatio,
    this.accent,
    this.accentWidthFactor = 0.0,
    this.secondaryAccent,
    this.showNoirDoubleLine = false,
  });

  final Color fill;
  final double borderRatio;
  final Color? accent;
  final double accentWidthFactor;
  final Color? secondaryAccent;
  final bool showNoirDoubleLine;

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
        // Legacy Sky/Blush/Gold and removed doodle frames fall through here.
        return StripChromeLook(
          fill: Colors.white,
          borderRatio: border,
        );
    }
  }
}

/// Thin accent rim or Noir double line overlay.
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
