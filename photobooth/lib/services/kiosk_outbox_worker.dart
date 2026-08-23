import 'dart:async';

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

  bool get isRunning => _timer != null;

  void start({Duration interval = const Duration(seconds: 30)}) {
    if (_timer != null) return;
    unawaited(drain());
    _timer = Timer.periodic(interval, (_) => unawaited(drain()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

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
          await _store.markAssetSynced(entry.entityId, atMs: _now().millisecondsSinceEpoch);
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
