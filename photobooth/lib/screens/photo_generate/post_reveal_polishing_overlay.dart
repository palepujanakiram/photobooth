import 'package:flutter/cupertino.dart'
    show CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';

import '../../utils/transformation_step_display.dart';
import 'photo_generate_viewmodel.dart';

/// Post–AI-reveal polish stages shown in the generation storyboard.
const List<String> kPostRevealPolishOrder = <String>[
  'scene_lighting',
  'face_relight',
  'frame_composite',
  'upscaling',
  'exif_stamp',
  'c2pa_sign',
  'storage',
];

/// User-facing label for a polish-stage chip (progress / generate screens).
String postRevealPolishStepCopy(String stageKey) {
  switch (stageKey) {
    case 'scene_lighting':
      return 'Matching scene lighting';
    case 'face_relight':
      return 'Relighting your face';
    case 'frame_composite':
      return 'Adding your frame';
    case 'upscaling':
      return 'Sharpening for print';
    case 'exif_stamp':
      return 'Branding';
    case 'c2pa_sign':
      return 'Signing authenticity';
    case 'storage':
      return 'Preparing print file';
    default:
      return transformationStepDisplayLabel(stageKey);
  }
}

Map<String, GenerationRunStepPreview> indexPolishStepsByStage(
  List<GenerationRunStepPreview> steps,
) {
  final byStage = <String, GenerationRunStepPreview>{};
  for (final s in steps) {
    byStage[canonicalPipelineStageKey(s.stage)] = s;
  }
  return byStage;
}

String resolveActivePolishStageKey(
  Map<String, GenerationRunStepPreview> byStage,
) {
  for (final k in kPostRevealPolishOrder) {
    final s = byStage[k];
    if (s != null && s.isActive) return k;
  }
  if (byStage['storage']?.isFinished == true) return 'storage';
  return kPostRevealPolishOrder.firstWhere(
    (k) => byStage[k]?.isFinished != true,
    orElse: () => 'storage',
  );
}

Color polishChipColor({required bool active, required bool finished}) {
  if (active) return CupertinoColors.activeBlue;
  if (finished) return Colors.lightGreenAccent.withValues(alpha: 0.9);
  return Colors.white30;
}

IconData polishChipIcon({required bool active, required bool finished}) {
  if (finished) return Icons.check_circle;
  if (active) return Icons.autorenew;
  return Icons.more_horiz;
}

/// Truthful post-processing mechanics after the AI preview is visible.
class PostRevealPolishingOverlay extends StatelessWidget {
  const PostRevealPolishingOverlay({
    required this.steps,
    super.key,
  });

  final List<GenerationRunStepPreview> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final byStage = indexPolishStepsByStage(steps);
    final activeKey = resolveActivePolishStageKey(byStage);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.wand_stars,
                    color: Colors.white70,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Finishing touches · ${postRevealPolishStepCopy(activeKey)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < kPostRevealPolishOrder.length; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      _PolishStageChip(
                        stageKey: kPostRevealPolishOrder[i],
                        preview: byStage[kPostRevealPolishOrder[i]],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolishStageChip extends StatelessWidget {
  const _PolishStageChip({
    required this.stageKey,
    required this.preview,
  });

  final String stageKey;
  final GenerationRunStepPreview? preview;

  @override
  Widget build(BuildContext context) {
    final finished = preview?.isFinished == true;
    final active = preview?.isActive == true;
    final color = polishChipColor(active: active, finished: finished);
    final icon = polishChipIcon(active: active, finished: finished);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            postRevealPolishStepCopy(stageKey),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
