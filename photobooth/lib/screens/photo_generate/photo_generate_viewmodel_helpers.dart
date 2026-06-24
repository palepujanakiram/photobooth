part of 'photo_generate_viewmodel.dart';

int resolveMaxRegenerationsAllowed(AppSettingsManager? mgr) {
  final n = mgr?.settings?.maxRegenerations;
  return (n != null && n > 0) ? n : AppConstants.kDefaultMaxRegenerations;
}

int computeTriesRemaining({
  required int maxAllowed,
  required int attemptsUsed,
}) {
  return (maxAllowed - attemptsUsed).clamp(0, maxAllowed);
}

Future<double?> aspectRatioFromXFile(XFile? file) async {
  if (file == null) return null;
  final path = file.path;
  try {
    final bytes = await file.readAsBytes();
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    final codec = await instantiateImageCodecFromBuffer(buffer);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();
    frame.image.dispose();
    codec.dispose();
    if (h <= 0) return null;
    return (w / h).clamp(0.35, 2.85);
  } catch (e) {
    AppLogger.debug('Could not read image aspect from $path: $e');
    return null;
  }
}

DateTime? parseGenerationRunStepStartedAt(dynamic v) {
  if (v is String && v.trim().isNotEmpty) {
    return DateTime.tryParse(v.trim());
  }
  return null;
}

List<GenerationRunStepPreview> parseGenerationRunStepsFromPayload(
  Map<String, dynamic> payload,
) {
  final stepsRaw = payload['steps'];
  if (stepsRaw is! List) return [];
  final rows = <Map<String, dynamic>>[];
  for (final e in stepsRaw) {
    if (e is! Map) continue;
    rows.add(Map<String, dynamic>.from(e));
  }
  rows.sort((a, b) {
    final ta = parseGenerationRunStepStartedAt(a['startedAt']);
    final tb = parseGenerationRunStepStartedAt(b['startedAt']);
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });
  return [
    for (final s in rows)
      GenerationRunStepPreview(
        stage: s['stage']?.toString() ?? 'step',
        status: s['status']?.toString() ?? '',
        previewUrl: SecureImageUrl.previewUrlFromStepMap(s),
      ),
  ];
}

bool generationRunStepsEqual(
  List<GenerationRunStepPreview> a,
  List<GenerationRunStepPreview> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].stage != b[i].stage ||
        a[i].status != b[i].status ||
        a[i].previewUrl != b[i].previewUrl) {
      return false;
    }
  }
  return true;
}

int? parseSseEventIndex(dynamic rawIdx) {
  if (rawIdx is int) return rawIdx;
  if (rawIdx is num) return rawIdx.toInt();
  return null;
}

int? parseSseDurationMs(dynamic rawMs) {
  if (rawMs is int) return rawMs;
  if (rawMs is num) return rawMs.toInt();
  return null;
}

/// User-facing error for [PhotoGenerateViewModel.tryDifferentStyle] (Sonar S3358).
String tryDifferentStyleErrorMessage(Object e) {
  if (e is ApiException) return e.userFacingMessage;
  if (e.toString().contains('Status 500')) {
    return 'Server error. Please try again or start over.';
  }
  return e.toString();
}

String generateImageErrorMessage(Object e) {
  if (e is ApiException) {
    return 'Generation failed: ${e.userFacingMessage}';
  }
  return 'Generation failed: ${e.toString()}';
}

List<GeneratedImage> generatedImagesFromParallelResult({
  required ParallelGenerationResult parallel,
  required ThemeModel theme,
  required String Function(int slotIndex) newImageId,
}) {
  final newImages = <GeneratedImage>[];
  for (var i = 0; i < parallel.imageUrlsBySlot.length; i++) {
    final url = parallel.imageUrlsBySlot[i];
    if (url.isEmpty) continue;
    newImages.add(GeneratedImage(
      id: newImageId(i),
      imageUrl: url,
      theme: theme,
      isSelected: true,
    ));
  }
  return newImages;
}
