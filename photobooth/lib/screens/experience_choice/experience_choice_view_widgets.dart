import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';

/// FotoZen card thumb — 2×2 of real AI theme samples (people + looks).
class ExperienceFotoZenThumb extends StatelessWidget {
  const ExperienceFotoZenThumb({
    super.key,
    this.width = 118,
    this.height = 118,
    this.muted = false,
  });

  final double width;
  final double height;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    const assets = AppStrings.experienceAiPreviewAssets;
    return Opacity(
      opacity: muted ? 0.45 : 1,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _AssetTile(assets[0])),
                        const SizedBox(width: 2),
                        Expanded(child: _AssetTile(assets[1])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _AssetTile(assets[2])),
                        const SizedBox(width: 2),
                        Expanded(child: _AssetTile(assets[3])),
                      ],
                    ),
                  ),
                ],
              ),
              const Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: _PreviewBadge(
                  label: AppStrings.experienceAiPreviewBadge,
                  color: Color(0xFF6B4EFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Classic card thumb — vertical 4-shot strip sample.
class ExperienceClassicThumb extends StatelessWidget {
  const ExperienceClassicThumb({
    super.key,
    this.width = 92,
    this.height = 118,
    this.muted = false,
    this.busy = false,
    required this.accent,
  });

  final double width;
  final double height;
  final bool muted;
  final bool busy;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: muted ? 0.45 : 1,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFFF5F0E8),
                child: Image.asset(
                  AppStrings.experienceClassicPreviewAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => _ClassicStripFallback(
                    accent: accent,
                    busy: busy,
                  ),
                ),
              ),
              if (busy)
                Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              const Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: _PreviewBadge(
                  label: AppStrings.experienceClassicPreviewBadge,
                  color: Color(0xFFD4922A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2A2540),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFF3A3555),
          child: Center(
            child: Icon(Icons.auto_awesome, color: Color(0xFFB8A8FF), size: 18),
          ),
        ),
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            shadows: [
              Shadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drawn strip if the classic PNG fails to load.
class _ClassicStripFallback extends StatelessWidget {
  const _ClassicStripFallback({required this.accent, required this.busy});

  final Color accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return ColoredBox(
        color: accent.withValues(alpha: 0.35),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFFF7F2EA),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xFFE8D9C8),
                      accent.withValues(alpha: 0.35),
                      i / 3,
                    ),
                    borderRadius: BorderRadius.circular(3),
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
