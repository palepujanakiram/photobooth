import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';

const String kEventMediaDirName = 'fotozen_event_media';

/// On-device storage for event pipeline renditions.
///
/// **A sibling of `fotozen_media/`, not a prefix inside it.** Writing event
/// media into [LocalMediaStore] would have three unwanted effects, and a
/// separate directory makes all three structurally impossible rather than
/// something to remember:
///
/// - `KioskOutboxWorker._enqueueUnsyncedMedia()` walks `LocalMediaStore.listAll()`
///   and enqueues **every** file it finds, so event photos would be uploaded by
///   the outbox this pipeline deliberately does not use.
/// - `KioskDiskGuard.measure()` would count them toward `kUnsyncedMediaCapBytes`
///   (2 GB), and `shouldBlockNewSessions()` would block the guest booth partway
///   through an event that never syncs.
/// - `KioskDiskGuard.pruneSynced()` deletes synced files after 7 days, which
///   would quietly destroy an event's reprintable media.
class EventMediaStore {
  EventMediaStore({Future<Directory> Function()? resolveDirectory})
      : _resolveDirectory = resolveDirectory ?? _defaultDirectory;

  final Future<Directory> Function() _resolveDirectory;

  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  static Future<Directory> _defaultDirectory() async {
    final root = await supportDirectory();
    final dir = Directory(p.join(root.path, kEventMediaDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Relative path a rendition is stored at: `{eventId}/{mediaId}-{kind}.jpg`.
  ///
  /// Deterministic on purpose — re-running a step overwrites its own output
  /// instead of leaking a new file every retry.
  static String relativePathFor({
    required String mediaId,
    required String kind,
    String? eventId,
  }) {
    final scope = (eventId == null || eventId.trim().isEmpty)
        ? 'unscoped'
        : _safeSegment(eventId);
    return '$scope/${_safeSegment(mediaId)}-${_safeSegment(kind)}.jpg';
  }

  /// Reduces an id to one safe path segment.
  ///
  /// Separators are stripped, but that alone is not enough: an id of `..`
  /// survives the character filter and would resolve *above* the store root
  /// once joined. Leading dots are therefore removed as well, so no segment can
  /// ever be `.` or `..`.
  static String _safeSegment(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    final safe = cleaned.replaceAll(RegExp(r'^\.+'), '');
    return safe.isEmpty ? 'x' : safe;
  }

  Future<Directory?> resolveRoot() async {
    try {
      return await _resolveDirectory();
    } catch (e) {
      AppLogger.debug('EventMediaStore: directory unavailable ($e)');
      return null;
    }
  }

  Future<File?> fileFor(String relativePath) async {
    final root = await resolveRoot();
    if (root == null) return null;
    return File(p.join(root.path, relativePath));
  }

  Future<File?> putBytes(String relativePath, List<int> bytes) async {
    final file = await fileFor(relativePath);
    if (file == null) return null;
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File?> getFile(String relativePath) async {
    final file = await fileFor(relativePath);
    if (file == null || !await file.exists()) return null;
    return file;
  }

  Future<bool> delete(String relativePath) async {
    try {
      final file = await fileFor(relativePath);
      if (file == null || !await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Total bytes held for an event, for the console's headroom display.
  Future<int> bytesForEvent(String eventId) async {
    final root = await resolveRoot();
    if (root == null) return 0;
    final dir = Directory(p.join(root.path, _safeSegment(eventId)));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Removes everything stored for an event — the operator's "event complete"
  /// purge. Nothing else deletes event media, by design.
  Future<int> purgeEvent(String eventId) async {
    final root = await resolveRoot();
    if (root == null) return 0;
    final dir = Directory(p.join(root.path, _safeSegment(eventId)));
    if (!await dir.exists()) return 0;
    var deleted = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) deleted++;
    }
    await dir.delete(recursive: true);
    return deleted;
  }
}
