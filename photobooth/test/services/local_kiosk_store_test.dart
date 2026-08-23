import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photobooth/services/local_kiosk_codec.dart';
import 'package:photobooth/services/local_kiosk_models.dart';
import 'package:photobooth/services/local_kiosk_store.dart';

void main() {
  late Directory dir;
  late LocalKioskStore store;
  var clock = 1;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_kiosk_');
    clock = 1;
    ids = 0;
    store = LocalKioskStore(
      resolveDirectory: () async => dir,
      nowMs: () => clock++,
      newId: () => 'ob-${ids++}',
    );
  });

  tearDown(() async {
    LocalKioskStore.resetInstance();
    LocalKioskStore.supportDirectory = getApplicationSupportDirectory;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  LocalSessionWrite sessionWrite(String id) => LocalSessionWrite(
        id: id,
        payload: {
          'id': id,
          'termsAccepted': true,
          'userImageUrl': 'data:image/jpeg;base64,AAA',
          'compressedImageUrl': 'data:image/jpeg;base64,BBB',
        },
        kioskCode: 'ODEON-01',
      );

  test('upsert session strips blobs, sets current, enqueues outbox', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    final json = await store.getSession('sess-1');
    expect(json!['id'], 'sess-1');
    expect(json.containsKey('userImageUrl'), isFalse);
    expect(json.containsKey('compressedImageUrl'), isFalse);
    expect(await store.currentSessionJson(), json);
    final pending = await store.pendingOutbox();
    expect(pending, hasLength(1));
    expect(pending.first.entityType, KioskOutboxEntity.session);
    expect(pending.first.entityId, 'sess-1');
  });

  test('session persist round-trip and SYNCING recovery', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    await store.claimPendingOutbox(limit: 1);
    final file = File('${dir.path}/ledger.json');
    expect(await file.exists(), isTrue);

    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    final json = await reloaded.getSession('sess-1');
    expect(json!['id'], 'sess-1');
    final pending = await reloaded.pendingOutbox();
    expect(pending, hasLength(1));
    expect(pending.first.status, KioskOutboxStatus.pending);
  });

  test('empty and corrupt ledger load as empty', () async {
    await File('${dir.path}/ledger.json').writeAsString('  ');
    expect(await store.getSession('x'), isNull);

    final badDir = await Directory.systemTemp.createTemp('fz_kiosk_bad_');
    addTearDown(() async {
      if (await badDir.exists()) await badDir.delete(recursive: true);
    });
    await File('${badDir.path}/ledger.json').writeAsString('{not-json');
    final bad = LocalKioskStore(resolveDirectory: () async => badDir);
    expect(await bad.getSession('x'), isNull);
  });

  test('directory failure keeps an in-memory ledger', () async {
    final broken = LocalKioskStore(
      resolveDirectory: () async => throw StateError('no dir'),
      newId: () => 'ob-x',
      nowMs: () => 9,
    );
    await broken.upsertSession(sessionWrite('s1'));
    expect((await broken.getSession('s1'))!['id'], 's1');
    expect(await broken.saveReceiptPdf('x', const [1]), isNull);
  });

  test('save failure is swallowed', () async {
    await Directory('${dir.path}/ledger.json').create();
    await store.upsertSession(sessionWrite('s1'));
    expect((await store.getSession('s1'))!['id'], 's1');
  });

  test('rejects empty ids and unknown outbox types', () async {
    expect(
      () => store.upsertSession(sessionWrite('  ')),
      throwsArgumentError,
    );
    expect(
      () => store.upsertPayment(id: '', sessionId: 's', payload: {}),
      throwsArgumentError,
    );
    expect(
      () => store.enqueueOutbox(
        entityType: 'nope',
        entityId: 'x',
        payload: {},
      ),
      throwsArgumentError,
    );
    expect(
      () => store.enqueueOutbox(
        entityType: KioskOutboxEntity.payment,
        entityId: ' ',
        payload: {},
      ),
      throwsArgumentError,
    );
  });

  test('payments prints receipts and invoice numbers', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    await store.upsertPayment(
      id: 'pay-1',
      sessionId: 'sess-1',
      payload: {'amount': 200, 'status': 'COMPLETED'},
    );
    await store.upsertPrintJob(
      id: 'pj-1',
      sessionId: 'sess-1',
      payload: {'copies': 1},
    );
    await store.upsertReceipt(
      id: 'rc-1',
      sessionId: 'sess-1',
      receiptNumber: 'FZ/ODEON-01/2627/00001',
      payload: {'total': 200},
    );
    expect(
      await store.allocateInvoiceNumber(
        kioskCode: 'ODEON-01',
        at: DateTime(2026, 7, 17),
      ),
      'FZ/ODEON-01/2627/00001',
    );
    expect(
      await store.allocateInvoiceNumber(
        kioskCode: 'ODEON-01',
        at: DateTime(2026, 7, 17),
      ),
      'FZ/ODEON-01/2627/00002',
    );
    final day = await store.countsForDay(DateTime.fromMillisecondsSinceEpoch(1));
    expect(day.sessions, 1);
    expect(day.payments, 1);
    expect(day.printJobs, 1);
    expect(day.receipts, 1);
    final onDay = await store.paymentsOnDay(
      DateTime.fromMillisecondsSinceEpoch(1),
    );
    expect(onDay, hasLength(1));
    expect(onDay.first.sessionId, 'sess-1');
    final other = await store.countsForDay(DateTime(1999, 1, 1));
    expect(other.sessions, 0);
    expect((await store.findReceiptForSession('sess-1'))!.id, 'rc-1');
    expect(await store.findReceiptForSession(' '), isNull);
    expect(await store.findReceiptForSession('missing'), isNull);
    expect((await store.paymentsForSession('sess-1')), hasLength(1));
    expect(await store.paymentsForSession(' '), isEmpty);
    final pdf = await store.saveReceiptPdf('rc-1', const [1, 2, 3]);
    expect(await pdf!.readAsBytes(), [1, 2, 3]);
    expect(await store.saveReceiptPdf('  ', const [1]), isNull);
  });

  test('outbox claim done and retry until failed', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    expect(await store.claimPendingOutbox(limit: 0), isEmpty);
    final claimed = await store.claimPendingOutbox(limit: 5);
    expect(claimed, hasLength(1));
    expect(claimed.first.status, KioskOutboxStatus.syncing);
    expect(await store.pendingOutbox(), isEmpty);

    await store.markOutboxFailed(claimed.first.id, maxAttempts: 2);
    expect((await store.pendingOutbox()).first.attempts, 1);

    final again = await store.claimPendingOutbox();
    await store.markOutboxFailed(again.first.id, maxAttempts: 2);
    expect(await store.pendingOutbox(), isEmpty);

    await store.markOutboxDone('missing');
    await store.markOutboxFailed('missing');
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.session,
      entityId: 'sess-1',
      payload: {'id': 'sess-1', 'attemptsUsed': 1},
    );
    final pending = await store.pendingOutbox();
    expect(pending, hasLength(1));
    await store.markOutboxDone(pending.first.id);
    expect(await store.pendingOutbox(), isEmpty);
  });

  test('clear current keeps the session row', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    await store.clearCurrentSession();
    expect(await store.currentSessionJson(), isNull);
    expect((await store.getSession('sess-1'))!['id'], 'sess-1');
  });

  test('init sets instance and ensureReady is idempotent', () async {
    final opened = await LocalKioskStore.init(
      resolveDirectory: () async => dir,
    );
    expect(identical(opened, LocalKioskStore.instance), isTrue);
    await opened.ensureReady();
    await opened.upsertSession(sessionWrite('sess-2'));
    expect(await opened.getSession('sess-2'), isNotNull);
  });

  test('default clocks and ids still persist', () async {
    final plain = LocalKioskStore(resolveDirectory: () async => dir);
    await plain.upsertSession(sessionWrite('sess-plain'));
    expect(await plain.getSession('sess-plain'), isNotNull);
  });

  test('missing current session id returns null', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    final file = File('${dir.path}/ledger.json');
    final decoded = jsonDecode(await file.readAsString()) as Map;
    decoded['currentSessionId'] = 'ghost';
    await file.writeAsString(jsonEncode(decoded));
    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    expect(await reloaded.currentSessionJson(), isNull);
  });

  test('optional flags and default invoice date', () async {
    await store.upsertSession(
      const LocalSessionWrite(
        id: 'quiet',
        payload: {'id': 'quiet'},
        setCurrent: false,
        enqueueOutbox: false,
      ),
    );
    expect(await store.currentSessionJson(), isNull);
    expect(await store.pendingOutbox(), isEmpty);
    await store.upsertSession(
      const LocalSessionWrite(
        id: 'quiet',
        payload: {'id': 'quiet', 'attemptsUsed': 1},
        paymentStatus: 'PENDING',
      ),
    );
    expect((await store.currentSessionJson())!['attemptsUsed'], 1);
    final number = await store.allocateInvoiceNumber(kioskCode: 'K1');
    expect(number, startsWith('FZ/'));
  });

  test('reloads entity rows and invoice sequences', () async {
    await store.upsertSession(sessionWrite('sess-1'));
    await store.upsertPayment(
      id: 'pay-1',
      sessionId: 'sess-1',
      payload: {'n': 1},
    );
    await store.upsertPrintJob(
      id: 'pj-1',
      sessionId: 'sess-1',
      payload: {'n': 1},
    );
    await store.upsertReceipt(
      id: 'rc-1',
      sessionId: 'sess-1',
      receiptNumber: 'FZ/K1/2627/00001',
      payload: {'n': 1},
    );
    await store.allocateInvoiceNumber(
      kioskCode: 'K1',
      at: DateTime(2026, 7, 17),
    );
    await store.upsertPayment(
      id: 'pay-1',
      sessionId: 'sess-1',
      payload: {'n': 2},
    );
    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    expect((await reloaded.getSession('sess-1'))!['id'], 'sess-1');
    expect(
      await reloaded.allocateInvoiceNumber(
        kioskCode: 'K1',
        at: DateTime(2026, 7, 17),
      ),
      'FZ/K1/2627/00002',
    );
  });

  test('creates missing ledger directory', () async {
    final missing = Directory('${dir.path}/nested/kiosk');
    final nested = LocalKioskStore(
      resolveDirectory: () async => missing,
      newId: () => 'ob-n',
      nowMs: () => 1,
    );
    await nested.upsertSession(sessionWrite('s1'));
    expect(await File('${missing.path}/ledger.json').exists(), isTrue);
  });

  test('default directory creates then reuses kiosk folder', () async {
    final support = await Directory.systemTemp.createTemp('fz_support_');
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    LocalKioskStore.supportDirectory = () async => support;
    final first = LocalKioskStore();
    await first.upsertSession(sessionWrite('s1'));
    expect(await Directory('${support.path}/fotozen_kiosk').exists(), isTrue);
    final second = LocalKioskStore();
    await second.upsertSession(sessionWrite('s2'));
    expect(await second.getSession('s2'), isNotNull);
  });

  test('codec and model helpers cover decode branches', () {
    expect(KioskLedgerData.fromJson(null).sessions, isEmpty);
    expect(KioskLedgerData.fromJson(<int>[1]).sessions, isEmpty);
    expect(jsonMap(null), isEmpty);
    expect(jsonMap({'a': 1}), {'a': 1});
    expect(jsonMap(<dynamic, dynamic>{'a': 1}), {'a': 1});
    expect(jsonInt(null), 0);
    expect(jsonInt(3), 3);
    expect(jsonInt(4.6), 5);

    const row = LocalEntityRow(
      id: 'p1',
      sessionId: 's1',
      payload: {'n': 1},
      createdAtMs: 1,
    );
    expect(row.toJson()['id'], 'p1');
    expect(LocalEntityRow.fromJson({'payload': 'nope'}).payload, isEmpty);

    final entry = KioskOutboxEntry.fromJson({
      'payload': <dynamic, dynamic>{'x': 1},
      'attempts': 2.2,
    });
    expect(entry.id, isEmpty);
    expect(entry.attempts, 2);
    expect(entry.copyWith(payload: {'z': 1}).payload, {'z': 1});
    expect(
      LocalSessionRow.fromJson({'payload': 3}).payload,
      isEmpty,
    );
    expect(KioskOutboxEntity.priority(KioskOutboxEntity.session), 0);
    expect(KioskOutboxEntity.priority(KioskOutboxEntity.asset), 4);
    expect(KioskOutboxEntity.priority('nope'), 9);
  });

  test('claims session before later payment and tracks synced assets', () async {
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.payment,
      entityId: 'pay-1',
      payload: {'id': 'pay-1'},
    );
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.session,
      entityId: 'sess-1',
      payload: {'id': 'sess-1'},
    );
    final claimed = await store.claimPendingOutbox(limit: 1);
    expect(claimed.single.entityType, KioskOutboxEntity.session);

    await store.markAssetSynced('generated/a.jpg', atMs: 42);
    expect((await store.syncedAssets())['generated/a.jpg'], 42);
    expect(await store.findOutbox(KioskOutboxEntity.session, 'sess-1'), isNotNull);
    expect(await store.findOutbox(KioskOutboxEntity.asset, 'missing'), isNull);
    await store.markAssetSynced('  ');
    expect((await store.syncedAssets()).containsKey(''), isFalse);
    await store.unmarkAssetSynced('generated/a.jpg');
    expect(await store.syncedAssets(), isEmpty);

    await store.markAssetSynced('generated/persist.jpg', atMs: 7);
    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    expect((await reloaded.syncedAssets())['generated/persist.jpg'], 7);
    await store.enqueueOutbox(
      entityType: KioskOutboxEntity.asset,
      entityId: 'generated/a.jpg',
      payload: {'prefix': 'generated', 'filename': 'a.jpg'},
    );
    expect(
      (await store.findOutbox(KioskOutboxEntity.asset, 'generated/a.jpg'))!
          .entityType,
      KioskOutboxEntity.asset,
    );
  });

  test('default directory miss is swallowed', () async {
    final def = LocalKioskStore();
    await def.upsertSession(sessionWrite('s-def'));
    // path_provider may throw in unit tests; in-memory still accepts the write.
    expect(await def.getSession('s-def'), isNotNull);
  });
}
