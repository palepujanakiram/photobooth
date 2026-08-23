import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/kiosk_disk_guard.dart';
import 'package:photobooth/services/kiosk_outbox_worker.dart';
import 'package:photobooth/services/local_kiosk_models.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/services/local_media_store.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  late Directory dir;
  late LocalKioskStore store;
  late LocalMediaStore media;
  late List<KioskIngestItem> ingested;
  late List<KioskAssetUpload> assets;
  late Object? nextError;
  var pruneCalls = 0;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_outbox_');
    ids = 0;
    store = LocalKioskStore(
      resolveDirectory: () async => Directory('${dir.path}/kiosk'),
      newId: () => 'ob-${ids++}',
    );
    media = LocalMediaStore(
      resolveDirectory: () async => Directory('${dir.path}/media'),
    );
    ingested = <KioskIngestItem>[];
    assets = <KioskAssetUpload>[];
    nextError = null;
    pruneCalls = 0;
  });

  tearDown(() async {
    LocalKioskStore.resetInstance();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  KioskOutboxWorker worker({
    Future<String?> Function()? code,
  }) {
    return KioskOutboxWorker(
      store: store,
      ingestEntities: (kioskCode, items) async {
        expect(kioskCode, 'K1');
        if (nextError != null) throw nextError!;
        ingested.addAll(items);
      },
      ingestAsset: (kioskCode, asset) async {
        expect(kioskCode, 'K1');
        if (nextError != null) throw nextError!;
        assets.add(asset);
      },
      resolveKioskCode: code ?? () async => 'k1',
      media: media,
      diskGuard: _CountingGuard(() => pruneCalls++),
      now: () => DateTime.utc(2026, 8, 23),
    );
  }

  test('isRetryableIngestError covers WAN, 412, and terminal 4xx', () {
    expect(isRetryableIngestError(ApiException('x')), isTrue);
    expect(isRetryableIngestError(ApiException('x', 500)), isTrue);
    expect(isRetryableIngestError(ApiException('x', 412)), isTrue);
    expect(isRetryableIngestError(ApiException('x', 429)), isTrue);
    expect(isRetryableIngestError(ApiException('x', 403)), isTrue);
    expect(isRetryableIngestError(ApiException('x', 409)), isFalse);
    expect(isRetryableIngestError(ApiException('x', 400)), isFalse);
    expect(
      isRetryableIngestError(ApiException(AppConstants.kErrorNetwork, 400)),
      isTrue,
    );
    expect(isRetryableIngestError(StateError('x')), isTrue);
    expect(
      KioskIngestItem(
        entityType: 'session',
        entityId: 's',
        payload: {'id': 's'},
      ).toJson()['entityType'],
      'session',
    );
  });

  test('drain is a no-op without a kiosk code', () async {
    expect(await worker(code: () async => null).drain(), 0);
    expect(await worker(code: () async => '  ').drain(), 0);
    final defaults = KioskOutboxWorker(
      store: store,
      ingestEntities: (code, items) async {},
      ingestAsset: (code, asset) async {},
      resolveKioskCode: () async => null,
    );
    expect(await defaults.drain(), 0);
    await expectLater(
      worker(code: () async => throw StateError('boom')).drain(),
      throwsA(isA<StateError>()),
    );
  });

  test('drains session rows then unsynced assets', () async {
    await store.upsertSession(
      const LocalSessionWrite(id: 'sess-1', payload: {'id': 'sess-1'}),
    );
    await media.putBytes(
      const LocalMediaRef(prefix: 'generated', filename: 'a.jpg'),
      Uint8List.fromList(const [9, 8, 7]),
    );
    final w = worker();
    expect(await w.drain(), 2);
    expect(ingested.single.entityType, KioskOutboxEntity.session);
    expect(assets.single.filename, 'a.jpg');
    expect(await store.pendingOutbox(), isEmpty);
    expect((await store.syncedAssets())['generated/a.jpg'], isNotNull);
    expect(pruneCalls, 1);
  });

  test('retries 412 and kills 409', () async {
    await store.upsertSession(
      const LocalSessionWrite(id: 'sess-1', payload: {'id': 'sess-1'}),
    );
    nextError = ApiException('session_missing', 412);
    final w = worker();
    expect(await w.drain(), 0);
    expect((await store.pendingOutbox()).single.attempts, 1);

    nextError = ApiException('conflict', 409);
    expect(await w.drain(), 0);
    expect(await store.pendingOutbox(), isEmpty);
  });

  test('missing or empty asset files still complete', () async {
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.asset,
      entityId: 'generated/missing.jpg',
      payload: {'prefix': 'generated', 'filename': 'missing.jpg'},
    );
    await Directory('${dir.path}/media/generated').create(recursive: true);
    await File('${dir.path}/media/generated/empty.jpg').writeAsBytes(const []);
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.asset,
      entityId: 'generated/empty.jpg',
      payload: {'prefix': 'generated', 'filename': 'empty.jpg'},
    );
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.asset,
      entityId: 'not-a-ref',
      payload: const <String, dynamic>{},
    );
    expect(await worker().drain(limit: 5), 3);
    expect(assets, isEmpty);
  });

  test('start drains and stop is idempotent', () async {
    await store.upsertSession(
      const LocalSessionWrite(id: 'sess-1', payload: {'id': 'sess-1'}),
    );
    final w = worker();
    w.start(interval: const Duration(hours: 1));
    expect(w.isRunning, isTrue);
    w.start(interval: const Duration(hours: 1));
    expect(await w.drain(), 0);
    w.stop();
    w.stop();
    expect(w.isRunning, isFalse);
    expect(ingested, isNotEmpty);
  });
}

class _CountingGuard extends KioskDiskGuard {
  _CountingGuard(this.onPrune);

  final void Function() onPrune;

  @override
  Future<int> pruneSynced() async {
    onPrune();
    return 0;
  }
}
