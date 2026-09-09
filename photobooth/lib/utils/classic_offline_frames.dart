import 'dart:io';
import 'dart:typed_data';

import '../models/kiosk_frame_model.dart';
import '../models/strip_models.dart';
import '../services/image_cache_service.dart';
import '../services/image_cache_source.dart';

typedef ClassicOverlayBytesLookup = Future<Uint8List?> Function(StripFrame frame);

/// Disk key for `GET /api/strip/filters` (per kiosk).
String stripFiltersCatalogDiskKey(String? kioskCode) {
  final raw = (kioskCode ?? '').trim().toUpperCase();
  final safe = raw.replaceAll(RegExp(r'[^A-Z0-9._-]'), '_');
  return 'strip_filters_${safe.isEmpty ? 'default' : safe}';
}

/// Stable image-cache key for a Classic catalog overlay PNG.
String? classicFrameOverlayCacheKey(
  String? frameId, {
  bool landscape = false,
}) {
  final id = frameId?.trim() ?? '';
  final dbId = classicFrameDbId(id);
  if (dbId == null) return catalogCacheKeyForFrame(id);
  if (isOccasionFrameId(id)) {
    return catalogCacheKeyForFrame(landscape ? '$dbId-land' : dbId);
  }
  if (isStrip3TemplateFrame(id)) {
    return catalogCacheKeyForFrame('$dbId-strip3');
  }
  if (isFrameStripVariantId(id)) {
    return catalogCacheKeyForFrame('$dbId-strip');
  }
  return catalogCacheKeyForFrame(dbId);
}

/// Classic look-picker rows that share kiosk assignment with the AI overlay.
List<StripFrame> classicFramesFromKioskFrame(KioskFrameModel frame) {
  final id = frame.id.trim();
  final name = frame.name.trim();
  if (id.isEmpty || name.isEmpty) return const [];
  final out = <StripFrame>[];
  final overlay = frame.overlayUrl.trim();
  if (overlay.isNotEmpty) {
    out.add(
      StripFrame(
        id: 'ai:$id',
        name: name,
        description: 'Classic 1-shot occasion overlay',
        kind: 'occasion',
        overlayUrl: overlay,
        landscapeOverlayUrl: frame.landscapeOverlayUrl.trim().isEmpty
            ? null
            : frame.landscapeOverlayUrl.trim(),
        shotCount: 1,
      ),
    );
  }
  if (frame.strip.has4) {
    out.add(
      StripFrame(
        id: 'fr:$id',
        name: '$name 6×2',
        description: 'Classic 4-shot dual 2×6',
        kind: 'template',
        overlayUrl: frame.strip.overlayUrl.trim(),
        shotCount: kStripShotCount,
        slots: frame.strip.slots,
      ),
    );
  }
  if (frame.strip.has3) {
    out.add(
      StripFrame(
        id: 'f3:$id',
        name: '$name 3-shot 6×2',
        description: 'Classic 3-shot dual 2×6',
        kind: 'template',
        overlayUrl: frame.strip.overlay3Url.trim(),
        shotCount: kStripShotCountThree,
        slots: frame.strip.slots3,
      ),
    );
  }
  return out;
}

/// Prefers kiosk-assigned occasion chrome when the strip catalog omitted it.
StripFiltersCatalog mergeOccasionFramesIntoCatalog(
  StripFiltersCatalog catalog,
  Iterable<KioskFrameModel> kioskFrames,
) {
  final existing = <String>{for (final frame in catalog.frames) frame.id};
  final extra = <StripFrame>[];
  for (final kiosk in kioskFrames) {
    for (final frame in classicFramesFromKioskFrame(kiosk)) {
      if (existing.add(frame.id)) extra.add(frame);
    }
  }
  if (extra.isEmpty) return catalog;
  return catalog.withFrames([...extra, ...catalog.frames]);
}

/// Reads a previously precached Classic overlay PNG (no network).
Future<Uint8List?> readClassicOverlayBytes(
  StripFrame frame, {
  Future<File?> Function(String url, {String? cacheKey})? cachedFile,
}) async {
  final url = frame.overlayUrl?.trim() ?? '';
  if (url.isEmpty) return null;
  if (!frame.isOccasion && !isStripTemplateFrame(frame.id)) return null;
  try {
    final lookup = cachedFile ?? _cachedClassicOverlayFile;
    final landscape = (frame.landscapeOverlayUrl ?? '').trim().isNotEmpty &&
        url == frame.landscapeOverlayUrl!.trim();
    final file = await lookup(
      url,
      cacheKey: classicFrameOverlayCacheKey(frame.id, landscape: landscape),
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

Future<File?> _cachedClassicOverlayFile(String url, {String? cacheKey}) {
  return ImageCacheService().getCachedFile(url, cacheKey: cacheKey);
}
