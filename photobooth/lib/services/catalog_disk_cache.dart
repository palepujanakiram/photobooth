import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Durable JSON catalog on the kiosk (themes, settings) for WAN-down boot.
class CatalogDiskCache {
  CatalogDiskCache({Future<Directory> Function()? resolveDirectory})
      : _resolveDirectory = resolveDirectory ?? _defaultDirectory;

  final Future<Directory> Function() _resolveDirectory;

  static final _safeKey = RegExp(r'^[a-zA-Z0-9._-]+$');

  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  static Future<Directory> _defaultDirectory() async {
    final root = await supportDirectory();
    final dir = Directory(p.join(root.path, 'catalog'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @visibleForTesting
  static String? sanitizeKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty || !_safeKey.hasMatch(trimmed)) return null;
    return trimmed;
  }

  Future<File?> _fileFor(String key) async {
    final safe = sanitizeKey(key);
    if (safe == null) return null;
    try {
      final dir = await _resolveDirectory();
      return File(p.join(dir.path, '$safe.json'));
    } catch (e, st) {
      AppLogger.debug('CatalogDiskCache: directory unavailable ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) async {
    final file = await _fileFor(key);
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(value), flush: true);
    } catch (e, st) {
      AppLogger.debug('CatalogDiskCache: write failed for $key ($e)');
      AppLogger.debug('$st');
    }
  }

  Future<Object?> readJson(String key) async {
    final file = await _fileFor(key);
    if (file == null || !await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (e, st) {
      AppLogger.debug('CatalogDiskCache: read failed for $key ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<void> delete(String key) async {
    final file = await _fileFor(key);
    if (file == null) return;
    try {
      await file.delete();
    } catch (e, st) {
      AppLogger.debug('CatalogDiskCache: delete failed for $key ($e)');
      AppLogger.debug('$st');
    }
  }
}
