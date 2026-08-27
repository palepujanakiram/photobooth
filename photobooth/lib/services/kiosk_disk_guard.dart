import '../utils/app_strings.dart';
import 'local_kiosk_models.dart';
import 'local_kiosk_store.dart';
import 'local_media_store.dart';

const kUnsyncedMediaCapBytes = 2 * 1024 * 1024 * 1024;
const kSyncedMediaRetention = Duration(days: 7);

class KioskDiskStatus {
  const KioskDiskStatus({
    required this.unsyncedBytes,
    required this.syncedBytes,
    required this.capBytes,
  });

  final int unsyncedBytes;
  final int syncedBytes;
  final int capBytes;

  bool get isCritical => unsyncedBytes >= capBytes;

  String get staffMessage => AppStrings.staffDiskFull;
}

/// Caps unsynced guest JPEGs at 2 GB and prunes synced files after 7 days.
class KioskDiskGuard {
  KioskDiskGuard({
    LocalKioskStore? store,
    LocalMediaStore? media,
    this.capBytes = kUnsyncedMediaCapBytes,
    this.retention = kSyncedMediaRetention,
    int Function()? nowMs,
  })  : _store = store,
        _media = media,
        _nowMs = nowMs ?? _defaultNowMs;

  final LocalKioskStore? _store;
  final LocalMediaStore? _media;
  final int capBytes;
  final Duration retention;
  final int Function() _nowMs;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  static bool shouldBlockNewSessions(KioskDiskStatus status) =>
      status.isCritical;

  Future<KioskDiskStatus> measure() async {
    final store = _store;
    final media = _media;
    if (store == null || media == null) {
      return KioskDiskStatus(
        unsyncedBytes: 0,
        syncedBytes: 0,
        capBytes: capBytes,
      );
    }
    final synced = await store.syncedAssets();
    final listings = await media.listAll();
    var unsynced = 0;
    var syncedBytes = 0;
    for (final file in listings) {
      if (synced.containsKey(file.ref.relativePath)) {
        syncedBytes += file.bytes;
      } else {
        unsynced += file.bytes;
      }
    }
    return KioskDiskStatus(
      unsyncedBytes: unsynced,
      syncedBytes: syncedBytes,
      capBytes: capBytes,
    );
  }

  Future<int> pruneSynced() async {
    final store = _store;
    final media = _media;
    if (store == null || media == null) return 0;
    final cutoff = _nowMs() - retention.inMilliseconds;
    final synced = await store.syncedAssets();
    var deleted = 0;
    for (final entry in synced.entries) {
      if (entry.value > cutoff) continue;
      final existing = await store.findOutbox(
        KioskOutboxEntity.asset,
        entry.key,
      );
      if (existing != null &&
          existing.status != KioskOutboxStatus.done) {
        continue;
      }
      final ref = _refForRelative(entry.key);
      if (ref != null) {
        final ok = await media.delete(ref);
        if (ok) deleted++;
      }
      await store.unmarkAssetSynced(entry.key);
    }
    return deleted;
  }
}

LocalMediaRef? _refForRelative(String relative) {
  final slash = relative.indexOf('/');
  if (slash <= 0 || slash >= relative.length - 1) {
    return LocalMediaRef.parse(relative);
  }
  return LocalMediaRef.fromParts(
    relative.substring(0, slash),
    relative.substring(slash + 1),
  );
}
