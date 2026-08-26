import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/exceptions.dart';
import 'local_kiosk_models.dart';
import 'local_kiosk_store.dart';
import 'local_media_store.dart';
import 'local_session_skeleton.dart';
import 'kiosk_disk_guard.dart';

class KioskIngestItem {
  const KioskIngestItem({
    required this.entityType,
    required this.entityId,
    required this.payload,
  });

  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entityType': entityType,
        'entityId': entityId,
        'payload': payload,
      };
}

class KioskAssetUpload {
  const KioskAssetUpload({
    required this.prefix,
    required this.filename,
    required this.bytes,
  });

  final String prefix;
  final String filename;
  final List<int> bytes;
}

/// Progress for splash / staff manual sync UI.
class KioskOutboxSyncProgress {
  const KioskOutboxSyncProgress({
    required this.counts,
    required this.completedThisRun,
    required this.running,
  });

  final KioskOutboxSyncCounts counts;
  final int completedThisRun;
  final bool running;

  int get remaining => counts.open;
  int get failed => counts.failed;
}

class KioskOutboxDrainResult {
  const KioskOutboxDrainResult({
    required this.completed,
    required this.remaining,
    required this.failed,
  });

  final int completed;
  final int remaining;
  final int failed;

  bool get isCaughtUp => remaining == 0;
}

/// True when Fly is unreachable or the parent row is not on Fly yet.
bool isRetryableIngestError(Object error) {
  if (isWanDownSessionError(error)) return true;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 412 || code == 429 || code == 403;
  }
  return true;
}

/// Drains the kiosk ledger outbox into Fly ingest when WAN is up.
class KioskOutboxWorker {
  KioskOutboxWorker({
    required LocalKioskStore store,
    required Future<void> Function(String kioskCode, List<KioskIngestItem> items)
        ingestEntities,
    required Future<void> Function(String kioskCode, KioskAssetUpload asset)
        ingestAsset,
    required Future<String?> Function() resolveKioskCode,
    LocalMediaStore? media,
    KioskDiskGuard? diskGuard,
    DateTime Function()? now,
  })  : _store = store,
        _ingestEntities = ingestEntities,
        _ingestAsset = ingestAsset,
        _resolveKioskCode = resolveKioskCode,
        _media = media ?? LocalMediaStore(),
        _diskGuard = diskGuard,
        _now = now ?? DateTime.now;

  static KioskOutboxWorker? _instance;

  /// Process-wide worker started from [main] (null on web / before init).
  static KioskOutboxWorker? get instance => _instance;

  @visibleForTesting
  static void resetInstanceForTests() {
    _instance?.stop();
    _instance = null;
  }

  final LocalKioskStore _store;
  final Future<void> Function(String kioskCode, List<KioskIngestItem> items)
      _ingestEntities;
  final Future<void> Function(String kioskCode, KioskAssetUpload asset)
      _ingestAsset;
  final Future<String?> Function() _resolveKioskCode;
  final LocalMediaStore _media;
  final KioskDiskGuard? _diskGuard;
  final DateTime Function() _now;

  Timer? _timer;
  Future<void> _chain = Future<void>.value();
  bool _manualDrainActive = false;

  bool get isRunning => _timer != null;
  bool get isManualDrainActive => _manualDrainActive;

  void start({Duration interval = const Duration(seconds: 30)}) {
    _instance = this;
    if (_timer != null) return;
    unawaited(drain());
    _timer = Timer.periodic(interval, (_) => unawaited(drain()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  Future<KioskOutboxSyncCounts> syncCounts() => _store.outboxSyncCounts();

  Future<int> drain({int limit = 8}) {
    final done = Completer<int>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await _drainUnlocked(limit: limit));
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Requeue failures, enqueue media, then drain until caught up or stalled.
  Future<KioskOutboxDrainResult> drainUntilCaughtUp({
    void Function(KioskOutboxSyncProgress progress)? onProgress,
    int batchLimit = 8,
    int maxRounds = 250,
  }) {
    final done = Completer<KioskOutboxDrainResult>();
    _chain = _chain.then((_) async {
      _manualDrainActive = true;
      try {
        done.complete(
          await _drainUntilCaughtUpUnlocked(
            onProgress: onProgress,
            batchLimit: batchLimit,
            maxRounds: maxRounds,
          ),
        );
      } catch (e, st) {
        done.completeError(e, st);
      } finally {
        _manualDrainActive = false;
      }
    });
    return done.future;
  }

  Future<KioskOutboxDrainResult> _drainUntilCaughtUpUnlocked({
    required void Function(KioskOutboxSyncProgress progress)? onProgress,
    required int batchLimit,
    required int maxRounds,
  }) async {
    await _store.requeueOpenOutbox();
    await _enqueueUnsyncedMedia();
    var completed = 0;
    var stalledRounds = 0;

    void emit(KioskOutboxSyncCounts counts, {required bool running}) {
      onProgress?.call(
        KioskOutboxSyncProgress(
          counts: counts,
          completedThisRun: completed,
          running: running,
        ),
      );
    }

    var counts = await _store.outboxSyncCounts();
    emit(counts, running: true);

    for (var round = 0; round < maxRounds && counts.open > 0; round++) {
      final n = await _drainUnlocked(limit: batchLimit);
      completed += n;
      counts = await _store.outboxSyncCounts();
      emit(counts, running: true);
      if (n == 0) {
        stalledRounds++;
        if (stalledRounds >= 2) break;
      } else {
        stalledRounds = 0;
      }
    }

    counts = await _store.outboxSyncCounts();
    emit(counts, running: false);
    return KioskOutboxDrainResult(
      completed: completed,
      remaining: counts.open,
      failed: counts.failed,
    );
  }

  Future<int> _drainUnlocked({required int limit}) async {
    final code = (await _resolveKioskCode())?.trim().toUpperCase();
    if (code == null || code.isEmpty) return 0;
    await _enqueueUnsyncedMedia();
    final claimed = await _store.claimPendingOutbox(limit: limit);
    var n = 0;
    for (final entry in claimed) {
      final synced = await _syncEntry(code, entry);
      if (synced) {
        await _store.markOutboxDone(entry.id);
        if (entry.entityType == KioskOutboxEntity.asset) {
          await _store.markAssetSynced(
            entry.entityId,
            atMs: _now().millisecondsSinceEpoch,
          );
        }
        n++;
      }
    }
    await _diskGuard?.pruneSynced();
    return n;
  }

  Future<void> _enqueueUnsyncedMedia() async {
    final listings = await _media.listAll();
    if (listings.isEmpty) return;
    final synced = await _store.syncedAssets();
    for (final file in listings) {
      final path = file.ref.relativePath;
      if (synced.containsKey(path)) continue;
      final existing = await _store.findOutbox(KioskOutboxEntity.asset, path);
      if (existing != null) continue;
      await _store.enqueueOutbox(
        entityType: KioskOutboxEntity.asset,
        entityId: path,
        payload: <String, dynamic>{
          'prefix': file.ref.prefix,
          'filename': file.ref.filename,
        },
      );
    }
  }

  Future<bool> _syncEntry(String kioskCode, KioskOutboxEntry entry) async {
    try {
      if (entry.entityType == KioskOutboxEntity.asset) {
        await _syncAsset(kioskCode, entry);
      } else {
        await _ingestEntities(kioskCode, <KioskIngestItem>[
          KioskIngestItem(
            entityType: entry.entityType,
            entityId: entry.entityId,
            payload: entry.payload,
          ),
        ]);
      }
      return true;
    } catch (e) {
      final retry = isRetryableIngestError(e);
      await _store.markOutboxFailed(
        entry.id,
        maxAttempts: retry ? 8 : 1,
      );
      return false;
    }
  }

  Future<void> _syncAsset(String kioskCode, KioskOutboxEntry entry) async {
    final prefix = entry.payload['prefix'] as String? ?? '';
    final filename = entry.payload['filename'] as String? ?? '';
    final ref = LocalMediaRef.fromParts(prefix, filename) ??
        LocalMediaRef.parse('local-media://${entry.entityId}');
    if (ref == null) return;
    final file = await _media.getFile(ref);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    await _ingestAsset(
      kioskCode,
      KioskAssetUpload(
        prefix: ref.prefix,
        filename: ref.filename,
        bytes: bytes,
      ),
    );
  }
}
