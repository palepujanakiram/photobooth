import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/generation_eta_estimator.dart';

/// Front-and-center portrait wait clock with progress arc + ETA copy.
class GenerationWaitPortraitClock extends StatelessWidget {
  const GenerationWaitPortraitClock({
    super.key,
    required this.snapshot,
    this.compact = false,
  });

  final GenerationEtaSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ringSize = compact ? 108.0 : 132.0;
    final stroke = compact ? 7.0 : 9.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 360 : 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: CircularProgressIndicator(
                    value: snapshot.progressFraction,
                    strokeWidth: stroke,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _ringColor(snapshot.phase),
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _ringCenterLabel(snapshot),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 18 : 22,
                          height: 1.05,
                        ),
                      ),
                      if (!compact &&
                          snapshot.phase != GenerationEtaPhase.longWait) ...[
                        const SizedBox(height: 2),
                        Text(
                          snapshot.phase == GenerationEtaPhase.polishing
                              ? '~30 sec'
                              : formatGenerationEtaDuration(
                                  snapshot.estimatedRemainingSeconds,
                                ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            snapshot.primaryLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13 : 14,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            snapshot.contextLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: compact ? 11 : 12,
              height: 1.3,
            ),
          ),
          if (snapshot.showReassurance) ...[
            const SizedBox(height: 6),
            Icon(
              CupertinoIcons.sparkles,
              size: compact ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ],
        ],
      ),
    );
  }

  Color _ringColor(GenerationEtaPhase phase) {
    return switch (phase) {
      GenerationEtaPhase.polishing => const Color(0xFF5EEAD4),
      GenerationEtaPhase.longWait => const Color(0xFFFBBF24),
      GenerationEtaPhase.inProgress => const Color(0xFF60A5FA),
      GenerationEtaPhase.starting => const Color(0xFFA78BFA),
    };
  }

  String _ringCenterLabel(GenerationEtaSnapshot snapshot) {
    if (snapshot.phase == GenerationEtaPhase.polishing) {
      return 'Almost';
    }
    if (snapshot.phase == GenerationEtaPhase.longWait) {
      return 'Still\nworking';
    }
    if (snapshot.phase == GenerationEtaPhase.starting) {
      return formatGenerationEtaDuration(snapshot.estimatedTotalSeconds);
    }
    final pct = (snapshot.progressFraction * 100).round().clamp(5, 95);
    return '$pct%';
  }
}

/// Thin linear progress under the clock for kiosk layouts.
class GenerationWaitEtaLinearBar extends StatelessWidget {
  const GenerationWaitEtaLinearBar({
    super.key,
    required this.progressFraction,
  });

  final double progressFraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: progressFraction.clamp(0.04, 0.98),
        minHeight: 4,
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation<Color>(
          Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
