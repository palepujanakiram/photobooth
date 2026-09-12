import 'dart:typed_data';

/// One importable image, described **without reading its bytes**.
///
/// Every field here comes from a directory `stat` or a single MediaStore cursor,
/// which is what makes a rescan of a known card instant: the diff runs entirely
/// on this metadata and only genuinely-new candidates are ever opened.
class IngestCandidate {
  const IngestCandidate({
    required this.sourceId,
    required this.relativePath,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAtMs,
    required this.uri,
    this.capturedAtMs,
    this.mimeType,
    this.width,
    this.height,
    this.orientation,
  });

  /// Volume UUID for a card, or a stable folder identifier.
  final String sourceId;

  /// Path within the volume, e.g. `DCIM/100CANON/IMG_0631.JPG`.
  final String relativePath;

  final String displayName;
  final int sizeBytes;

  /// Filesystem mtime. Part of the dedupe key, **not** a capture time — the two
  /// diverge whenever a computer has touched the card.
  final int modifiedAtMs;

  /// Opaque handle the source uses to read this item (`content://…` or a path).
  final String uri;

  /// EXIF capture time. MediaStore supplies this as `datetaken`, so the card
  /// path populates it with no file read at all.
  final int? capturedAtMs;

  final String? mimeType;
  final int? width;
  final int? height;
  final int? orientation;

  /// Tier-1 dedupe key.
  ///
  /// Size and mtime are included deliberately. Path alone silently skips new
  /// photos after a card is reformatted and the camera's numbering resets to
  /// `IMG_0001` — a false negative, and the dangerous direction to be wrong in.
  String get sourceRef =>
      '$sourceId:$relativePath:$sizeBytes:$modifiedAtMs';

  /// Directory portion of [relativePath], `''` for a file at the volume root.
  String get folder {
    final i = relativePath.lastIndexOf('/');
    return i <= 0 ? '' : relativePath.substring(0, i);
  }

  /// Best available timestamp for sorting a review grid.
  int get sortKey => capturedAtMs ?? modifiedAtMs;
}

/// A place images can be imported from.
///
/// The seam that lets the storage mechanism change without the pipeline caring:
/// MediaStore on a card, a plain directory, the gallery picker, or a future
/// CCAPI camera all implement this and nothing downstream differs.
abstract class IngestSource {
  /// Stable identity of this source — a volume UUID for a card.
  String get id;

  /// Operator-facing label, e.g. `SD card (1E6F-0961)`.
  String get label;

  /// Which [MediaSource] rows from this source are recorded under.
  String get sourceKind;

  /// Everything this source currently holds, metadata only.
  Future<List<IngestCandidate>> listAll();

  /// Reads [length] bytes from [offset]. Used to sample head and tail for the
  /// content key without reading a 6 MB file end to end.
  ///
  /// There is deliberately no whole-file read: the downscaler is handed
  /// [IngestCandidate.uri] and decodes natively, so a 6 MB original never
  /// crosses the platform boundary or sits in the Dart heap.
  Future<Uint8List> readRange(IngestCandidate candidate, int offset, int length);
}

/// MIME types worth importing.
///
/// RAW is excluded deliberately. In RAW+JPEG mode a camera writes
/// `IMG_0631.CR3` beside `IMG_0631.JPG` — the same photograph twice — so taking
/// the JPEG avoids double-importing every frame with no pair-matching logic. On
/// top of that, on-device RAW decode is slow and format-specific, and
/// MediaStore's RAW indexing is inconsistent across vendors.
abstract final class IngestMimeTypes {
  static const Set<String> importable = <String>{
    'image/jpeg',
    'image/heic',
    'image/heif',
    'image/png',
  };

  /// Extensions checked when a source reports no usable MIME type.
  static const Set<String> importableExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.heic',
    '.heif',
    '.png',
  };

  /// Recognised RAW extensions, so a RAW-only card can be *reported* as such
  /// rather than looking indistinguishable from a failed scan.
  static const Set<String> rawExtensions = <String>{
    '.cr2',
    '.cr3',
    '.arw',
    '.nef',
    '.raf',
    '.orf',
    '.rw2',
    '.dng',
    '.srw',
  };

  static String? _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot).toLowerCase();
  }

  static bool isImportable(IngestCandidate c) {
    final mime = c.mimeType?.trim().toLowerCase();
    if (mime != null && mime.isNotEmpty) {
      if (importable.contains(mime)) return true;
      // An explicit non-image MIME is authoritative; do not second-guess it by
      // filename, or a `.jpg`-named video sneaks into the queue.
      if (mime.startsWith('image/')) return false;
      return false;
    }
    final ext = _extension(c.displayName);
    return ext != null && importableExtensions.contains(ext);
  }

  static bool isRaw(IngestCandidate c) {
    final ext = _extension(c.displayName);
    return ext != null && rawExtensions.contains(ext);
  }
}
