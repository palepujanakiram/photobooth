import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

const kLocalGuestMediaPrefixes = <String>{
  'generated',
  'previews',
  'user-uploads',
  'fotoflashback',
  'surprise-me',
};

/// `{prefix}/{uuid}.jpg` guest photo on kiosk disk.
class LocalMediaRef {
  const LocalMediaRef({required this.prefix, required this.filename});

  final String prefix;
  final String filename;

  String get relativePath => '$prefix/$filename';

  /// Parses `/api/img/{prefix}/{file}` or `local-media://{prefix}/{file}`.
  static LocalMediaRef? parse(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    var path = trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'local-media') {
        final host = uri.host;
        final pathSegs =
            uri.path.split('/').where((s) => s.isNotEmpty).toList();
        if (host.isNotEmpty && pathSegs.isNotEmpty) {
          return _fromParts(host, pathSegs.join('/'));
        }
        if (pathSegs.length >= 2) {
          return _fromParts(pathSegs[0], pathSegs.sublist(1).join('/'));
        }
        return null;
      }
      path = uri.path;
    }
    const marker = '/api/img/';
    final idx = path.indexOf(marker);
    final rest = idx >= 0 ? path.substring(idx + marker.length) : path;
    final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) return null;
    return _fromParts(parts[0], parts.sublist(1).join('/'));
  }

  static LocalMediaRef? fromParts(String prefix, String filename) {
    return _fromParts(prefix, filename);
  }

  static LocalMediaRef? _fromParts(String prefix, String filename) {
    if (!kLocalGuestMediaPrefixes.contains(prefix)) return null;
    if (filename.contains('..') || filename.contains('/')) return null;
    if (!RegExp(r'^[\w-]+\.\w+$').hasMatch(filename)) return null;
    return LocalMediaRef(prefix: prefix, filename: filename);
  }
}

/// Writes guest JPEGs as `{support}/fotozen_media/{prefix}/{uuid}.ext`.
class LocalMediaStore {
  LocalMediaStore({Future<Directory> Function()? resolveDirectory})
      : _resolveDirectory = resolveDirectory ?? _defaultDirectory;

  final Future<Directory> Function() _resolveDirectory;

  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  static Future<Directory> _defaultDirectory() async {
    final root = await supportDirectory();
    final dir = Directory(p.join(root.path, 'fotozen_media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @visibleForTesting
  Future<Directory?> resolveRoot() async {
    try {
      return await _resolveDirectory();
    } catch (e, st) {
      AppLogger.debug('LocalMediaStore: directory unavailable ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<File?> fileFor(LocalMediaRef ref) async {
    final root = await resolveRoot();
    if (root == null) return null;
    final dir = Directory(p.join(root.path, ref.prefix));
    return File(p.join(dir.path, ref.filename));
  }

  Future<File?> putBytes(LocalMediaRef ref, List<int> bytes) async {
    final file = await fileFor(ref);
    if (file == null) return null;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      AppLogger.debug('LocalMediaStore: write failed (${ref.relativePath}) $e');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<File?> getFile(LocalMediaRef ref) async {
    final file = await fileFor(ref);
    if (file == null || !await file.exists()) return null;
    return file;
  }

  /// Local file for an `/api/img/...` URL, if this kiosk wrote it.
  Future<File?> fileForUrl(String url) async {
    final ref = LocalMediaRef.parse(url);
    if (ref == null) return null;
    return getFile(ref);
  }

  Future<bool> delete(LocalMediaRef ref) async {
    final file = await getFile(ref);
    if (file == null) return false;
    try {
      await file.delete();
      return true;
    } catch (e, st) {
      AppLogger.debug('LocalMediaStore: delete failed (${ref.relativePath}) $e');
      AppLogger.debug('$st');
      return false;
    }
  }

  Future<List<LocalMediaListing>> listAll() async {
    final root = await resolveRoot();
    if (root == null || !await root.exists()) return const <LocalMediaListing>[];
    final out = <LocalMediaListing>[];
    try {
      for (final prefix in kLocalGuestMediaPrefixes) {
        await _listPrefix(root, prefix, out);
      }
    } catch (e, st) {
      AppLogger.debug('LocalMediaStore: list failed ($e)');
      AppLogger.debug('$st');
    }
    return out;
  }

  Future<void> _listPrefix(
    Directory root,
    String prefix,
    List<LocalMediaListing> out,
  ) async {
    final dir = Directory(p.join(root.path, prefix));
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final ref = LocalMediaRef.fromParts(prefix, p.basename(entity.path));
      if (ref == null) continue;
      final stat = await entity.stat();
      out.add(
        LocalMediaListing(
          ref: ref,
          bytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }
  }
}

class LocalMediaListing {
  const LocalMediaListing({
    required this.ref,
    required this.bytes,
    required this.modifiedAtMs,
  });

  final LocalMediaRef ref;
  final int bytes;
  final int modifiedAtMs;
}

/// Walks JSON for `/api/img/{prefix}/{file}` and `local-media://` URLs.
List<LocalMediaRef> collectLocalMediaRefs(Object? value) {
  final out = <LocalMediaRef>[];
  final seen = <String>{};
  _walkMediaRefs(value, out, seen);
  return out;
}

void _walkMediaRefs(
  Object? value,
  List<LocalMediaRef> out,
  Set<String> seen,
) {
  if (value is String) {
    final ref = LocalMediaRef.parse(value);
    if (ref != null && seen.add(ref.relativePath)) {
      out.add(ref);
    }
    return;
  }
  if (value is Map) {
    for (final item in value.values) {
      _walkMediaRefs(item, out, seen);
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _walkMediaRefs(item, out, seen);
    }
  }
}
