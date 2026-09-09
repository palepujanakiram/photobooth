/// The stored versions of one photograph.
///
/// The original is never copied off the card — only these derivatives live on
/// the device, which is what takes a 3,000-frame event from ~18 GB to ~4 GB.
abstract final class RenditionKind {
  /// Downscaled print-ready copy written at import.
  static const String source = 'source';

  /// Result of the AI step.
  static const String ai = 'ai';

  /// Result of the frame step.
  static const String framed = 'framed';

  /// Grid thumbnail, ~320 px short side and ~30 KB.
  ///
  /// Roughly 20x less to read than the print derivative and a trivial decode,
  /// which is the difference between a smooth grid and an unusable one on the
  /// Amlogic box. It costs no extra read: the downscaler already holds the full
  /// bitmap and the compositor already holds the finished canvas, so each emits
  /// two encodes from one decode.
  ///
  /// Deliberately **not** in [printPriority] — a 320 px thumbnail must never
  /// reach a printer.
  static const String thumb = 'thumb';

  /// Order the print step resolves in — best available wins.
  ///
  /// So a failed frame step still prints the AI result, and an AI-off event
  /// prints the source derivative, rather than either case blocking the print.
  static const List<String> printPriority = <String>[framed, ai, source];

  static const List<String> all = <String>[source, ai, framed, thumb];

  /// Short side of a [thumb], in pixels.
  static const int thumbShortSide = 320;

  static bool isValid(String kind) => all.contains(kind);
}

class MediaRendition {
  const MediaRendition({
    required this.mediaId,
    required this.kind,
    required this.path,
    required this.createdAtMs,
    this.width,
    this.height,
    this.bytes,
  });

  final String mediaId;

  /// One of [RenditionKind].
  final String kind;

  /// Path relative to the event media store root.
  final String path;

  final int? width;
  final int? height;
  final int? bytes;
  final int createdAtMs;

  Map<String, Object?> toRow() => <String, Object?>{
        'media_id': mediaId,
        'kind': kind,
        'path': path,
        'width': width,
        'height': height,
        'bytes': bytes,
        'created_at_ms': createdAtMs,
      };

  factory MediaRendition.fromRow(Map<String, Object?> row) {
    return MediaRendition(
      mediaId: (row['media_id'] ?? '').toString(),
      kind: (row['kind'] ?? '').toString(),
      path: (row['path'] ?? '').toString(),
      width: row['width'] as int?,
      height: row['height'] as int?,
      bytes: row['bytes'] as int?,
      createdAtMs: (row['created_at_ms'] as int?) ?? 0,
    );
  }

  /// Picks the rendition a print should use from [available].
  ///
  /// Returns null only when nothing has been stored for the item at all.
  static MediaRendition? bestForPrint(Iterable<MediaRendition> available) {
    final byKind = <String, MediaRendition>{
      for (final r in available) r.kind: r,
    };
    for (final kind in RenditionKind.printPriority) {
      final match = byKind[kind];
      if (match != null) return match;
    }
    return null;
  }
}
