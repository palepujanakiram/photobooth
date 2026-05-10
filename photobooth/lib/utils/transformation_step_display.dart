import 'package:flutter/material.dart';

/// Display labels for [transformation_steps].[].stage (admin transformation detail).
///
/// Unknown stages fall back to the raw [stage] string at call sites.
const Map<String, String> kTransformationStepDisplayLabels = {
  'preprocess': 'Preprocessing',
  'ai': 'AI generation',
  'ai_generation': 'AI generation',
  'upscale': 'Upscale',
  'depth_enhance': 'Depth enhance',
  'scene_lighting': 'Scene lighting',
  'face_relight': 'Face relight',
  'image_enhance': 'Image enhance',
  'storage': 'Storage',
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
    case 'preprocess':
      return Icons.tune;
    case 'ai':
    case 'ai_generation':
      return Icons.auto_awesome;
    case 'upscale':
    case 'image_enhance':
    case 'depth_enhance':
      return Icons.hd_outlined;
    case 'scene_lighting':
    case 'face_relight':
      return Icons.wb_sunny_outlined;
    case 'storage':
      return Icons.cloud_upload_outlined;
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
