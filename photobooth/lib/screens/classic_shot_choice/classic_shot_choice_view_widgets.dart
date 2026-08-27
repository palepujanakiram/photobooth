import 'package:flutter/material.dart';

import '../../utils/classic_shot_choice_options.dart';
import '../../utils/classic_shot_mode.dart';

/// Large sample strip for one Classic shot mode on the choice screen.
class ClassicShotPreviewCard extends StatelessWidget {
  const ClassicShotPreviewCard({
    super.key,
    required this.option,
    required this.onTap,
    this.accent = const Color(0xFFD4922A),
  });

  final ClassicShotChoiceOption option;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isSingle = option.mode == ClassicShotMode.single6x4;
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: isSingle ? 0.74 : 0.34,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: const Color(0xFFF5F0E8),
                            child: Image.asset(
                              option.previewAsset,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorBuilder: (_, __, ___) =>
                                  ClassicShotStripFallback(
                                shotCount: option.mode.shotCount,
                                accent: accent,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: _Badge(label: option.badge, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                option.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                option.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(option.startLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.85)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Drawn strip when a preview asset fails to load.
class ClassicShotStripFallback extends StatelessWidget {
  const ClassicShotStripFallback({
    super.key,
    required this.shotCount,
    required this.accent,
  });

  final int shotCount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final n = shotCount.clamp(1, 4);
    return ColoredBox(
      color: const Color(0xFFF7F2EA),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xFFE8D9C8),
                      accent.withValues(alpha: 0.35),
                      n == 1 ? 0.4 : i / (n - 1),
                    ),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
