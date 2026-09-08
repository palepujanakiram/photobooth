import 'package:flutter/material.dart';

/// Dim over the live preview while the pose timer runs. Kept light so faces
/// stay visible under the numeral.
const double kCaptureCountdownScrimAlpha = 0.18;

/// Grey disc behind the seconds. Lower than the old 70% so it does not paint
/// over skin as a solid blob.
const double kCaptureCountdownDiscAlpha = 0.38;

/// Offset from the top of the viewfinder so the timer sits above heads.
const double kCaptureCountdownTopPadding = 20;

/// Pose countdown (10, 9, 8…) at the top of the preview, not over faces.
class CaptureCountdownOverlay extends StatelessWidget {
  const CaptureCountdownOverlay({
    super.key,
    required this.countdownValue,
    this.headline,
  });

  final int countdownValue;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final intro = headline;
    return ColoredBox(
      color: Colors.black.withValues(alpha: kCaptureCountdownScrimAlpha),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: kCaptureCountdownTopPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (intro != null) ...[
                Text(
                  intro,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: kCaptureCountdownDiscAlpha),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$countdownValue',
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
