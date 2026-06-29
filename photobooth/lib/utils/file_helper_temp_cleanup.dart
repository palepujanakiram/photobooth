/// Filename rules for [FileHelper.cleanupTempImages] (unit-testable).
bool shouldDeleteTempImageFileName(String fileName) {
  final lower = fileName.toLowerCase();
  final isImage = lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp');
  if (!isImage) {
    return false;
  }

  const prefixes = [
    'upload_',
    'transformed_',
    'print_',
    'capture_',
    'captured_',
    'photo_',
    'img_',
    'pxl_',
    'cap',
    'camera_',
    'uvc_raster_',
    'streamcap_',
  ];

  for (final prefix in prefixes) {
    if (lower.startsWith(prefix)) {
      return true;
    }
  }

  if (lower.contains('capture') || lower.contains('camera')) {
    return true;
  }

  return false;
}
