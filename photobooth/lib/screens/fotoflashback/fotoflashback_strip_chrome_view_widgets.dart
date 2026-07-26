import 'package:flutter/material.dart';

/// Dual-strip chrome for Classic / Sky / Blush / Gold / Noir previews.
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

  static StripChromeLook forFrame(String frameId) {
    switch (frameId) {
      // API id `ticket` → Sky (blue blush twin), thin elegant rim.
      case 'ticket':
        return const StripChromeLook(
          fill: Color(0xFFEAF2FF),
          borderRatio: 0.028,
          accent: Color(0xFF6B9FE8),
          accentWidthFactor: 0.011,
        );
      case 'blush':
        return const StripChromeLook(
          fill: Color(0xFFFFF0F3),
          borderRatio: 0.028,
          accent: Color(0xFFE8919A),
          accentWidthFactor: 0.011,
        );
      case 'gold':
        return const StripChromeLook(
          fill: Color(0xFFF7F0E0),
          borderRatio: 0.028,
          accent: Color(0xFFD4AF6A),
          accentWidthFactor: 0.011,
        );
      case 'noir':
        return const StripChromeLook(
          fill: Color(0xFF121216),
          borderRatio: 0.055,
          accent: Color(0xFFC8C8D0),
          accentWidthFactor: 0.016,
          secondaryAccent: Color(0xFF6E6E78),
          showNoirDoubleLine: true,
        );
      case 'classic':
      default:
        return const StripChromeLook(
          fill: Colors.white,
          borderRatio: 4 / 600,
        );
    }
  }
}

/// Thin accent rim (and Noir double line) drawn over the strip.
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

    final accentW = (width * look.accentWidthFactor).clamp(1.0, 2.5);
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.all(borderPad),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: accent, width: accentW),
          ),
          child: look.showNoirDoubleLine && look.secondaryAccent != null
              ? Padding(
                  padding: EdgeInsets.all(accentW + 1.2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: look.secondaryAccent!,
                        width: (accentW * 0.65).clamp(0.8, 1.8),
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
