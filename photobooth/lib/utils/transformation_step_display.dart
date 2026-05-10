import 'package:flutter/material.dart';

/// Display labels for [transformation_steps].[].stage (admin transformation detail).
///
/// Unknown stages fall back to the raw [stage] string at call sites.
const Map<String, String> kTransformationStepDisplayLabels = {
  'background_removal': 'Background removal',
  'frame_composite': 'Frame composite',
  'exif_stamp': 'EXIF stamp',
  'c2pa_sign': 'C2PA signing',
};

String transformationStepDisplayLabel(String stage) {
  final key = stage.trim();
  if (key.isEmpty) return stage;
  return kTransformationStepDisplayLabels[key] ?? stage;
}

IconData transformationStepIcon(String stage) {
  switch (stage.trim()) {
    case 'background_removal':
      return Icons.auto_fix_high;
    case 'frame_composite':
      return Icons.filter_frames;
    case 'exif_stamp':
      return Icons.sticky_note_2_outlined;
    case 'c2pa_sign':
      return Icons.verified_user_outlined;
    default:
      return Icons.more_horiz;
  }
}
