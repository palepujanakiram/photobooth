import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../models/event_pipeline/media_item.dart';
import '../../../utils/event_bulk_import.dart';
import 'ingest_source.dart';

/// Reads importable images from a directory tree.
///
/// Two jobs: it is the fallback for a card that turns out to be directly
/// readable, and it covers a LAN drop folder. It is also what makes the whole
/// ingest path testable with no platform channel — every rule in the diff,
/// worker and UI is exercised against a real directory.
class FolderIngestSource implements IngestSource {
  FolderIngestSource({
    required this.directory,
    String? id,
    String? label,
    this.sourceKind = MediaSource.folder,
  })  : id = id ?? directory.path,
        label = label ?? p.basename(directory.path);

  final Directory directory;

  @override
  final String id;

  @override
  final String label;

  @override
  final String sourceKind;

  @override
  Future<List<IngestCandidate>> listAll() async {
    if (!await directory.exists()) return const <IngestCandidate>[];
    final out = <IngestCandidate>[];
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final candidate = await _describe(entity);
      if (candidate != null) out.add(candidate);
    }
    return out;
  }

  Future<IngestCandidate?> _describe(File file) async {
    try {
      final stat = await file.stat();
      final relative = p
          .relative(file.path, from: directory.path)
          .replaceAll(r'\', '/');
      final name = p.basename(file.path);
      // Skip macOS AppleDouble stubs. MediaStore filters these for free; a raw
      // directory walk does not, and they are 4 KB files that decode to nothing.
      if (name.startsWith('._')) return null;
      return IngestCandidate(
        sourceId: id,
        relativePath: relative,
        displayName: name,
        sizeBytes: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        uri: file.path,
        capturedAtMs: await _capturedAt(file, stat),
      );
    } catch (_) {
      return null;
    }
  }

  /// EXIF `DateTimeOriginal`, falling back to mtime.
  ///
  /// Reuses [parseJpegExifDateTime], the zero-dependency APP1 scan already in
  /// the codebase, over the first 64 KiB rather than the whole file.
  Future<int?> _capturedAt(File file, FileStat stat) async {
    try {
      final head = await _read(file, 0, ContentKeySampleBytes.value);
      final parsed = parseJpegExifDateTime(head);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    } catch (_) {
      // A malformed header is not a reason to skip an otherwise good photo.
    }
    return stat.modified.millisecondsSinceEpoch;
  }

  @override
  Future<Uint8List> readRange(
    IngestCandidate candidate,
    int offset,
    int length,
  ) {
    return _read(File(candidate.uri), offset, length);
  }

  static Future<Uint8List> _read(File file, int offset, int length) async {
    final handle = await file.open();
    try {
      if (offset > 0) await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }
}

/// Sample size shared with the content key, kept here to avoid a cycle between
/// the source and diff libraries.
abstract final class ContentKeySampleBytes {
  static const int value = 64 * 1024;
}
