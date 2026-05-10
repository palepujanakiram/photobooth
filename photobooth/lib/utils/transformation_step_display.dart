import 'package:flutter/material.dart';

/// Display labels for [transformation_steps].[].stage (admin transformation detail).
///
/// Unknown stages fall back to the raw [stage] string at call sites.
const Map<String, String> kTransformationStepDisplayLabels = {
  // Leading client-only funnel slot (live capture in the booth frame).
  'device_capture': 'In frame',
  // Funnel labels (aligned with backend `stage` strings + per-stage CDN previews).
  'preprocessing': 'Captured',
  'preprocess': 'Captured',
  'background_removal': 'Cut out',
  'ai': 'AI rendered',
  'ai_generation': 'AI rendered',
  'scene_lighting': 'Lit',
  'face_relight': 'Relit',
  'frame_composite': 'Framed',
  'exif_stamp': 'Branded',
  'c2pa_sign': 'Signed',
  'storage': 'Ready to print',
  'upscale': 'Upscale',
  'depth_enhance': 'Depth enhance',
  'image_enhance': 'Image enhance',
};

String transformationStepDisplayLabel(String stage) {
  final key = stage.trim();
  if (key.isEmpty) return stage;
  return kTransformationStepDisplayLabels[key] ?? stage;
}

IconData transformationStepIcon(String stage) {
  switch (stage.trim()) {
    case 'device_capture':
      return Icons.crop_portrait;
    case 'preprocessing':
    case 'preprocess':
      return Icons.crop_free;
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
