import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/local_kiosk_db.dart';
import 'package:photobooth/services/local_kiosk_settlement.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/services/local_receipt_pdf.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  late Directory dir;
  late LocalKioskStore store;
  late LocalKioskSettlement settlement;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_settle_');
    ids = 0;
    store = LocalKioskStore(
      resolveDirectory: () async => dir,
      nowMs: () => 1,
      newId: () => 'ob-${ids++}',
    );
    settlement = LocalKioskSettlement(
      store: store,
      newId: () => 'n-${ids++}',
      now: () => DateTime.utc(2026, 7, 17),
    );
  });

  tearDown(() async {
    LocalKioskStore.resetInstance();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('records cash payment and print job', () async {
    await settlement.recordApprovedPayment(
      paymentId: 'pay-1',
      sessionId: 'sess-1',
      amount: -5,
      paymentMode: 'cash',
    );
    final pays = await store.paymentsForSession('sess-1');
    expect(pays.single.payload['status'], 'APPROVED');
    expect(pays.single.payload['amount'], 0);
    expect(pays.single.payload['paymentMode'], 'CASH');
    expect((await store.getSession('sess-1'))!['paymentStatus'], 'APPROVED');

    final printId = await settlement.recordPrintJob(
      sessionId: 'sess-1',
      imageUrl: '/api/img/generated/a.jpg',
      copies: 0,
    );
    expect(printId, startsWith('n-'));
  });

  test('rejects empty ids and bad payment mode', () async {
    expect(
      () => settlement.recordApprovedPayment(
        paymentId: ' ',
        sessionId: 's',
        amount: 1,
        paymentMode: 'CASH',
      ),
      throwsArgumentError,
    );
    expect(
      () => settlement.recordApprovedPayment(
        paymentId: 'p',
        sessionId: 's',
        amount: 1,
        paymentMode: 'WIRE',
      ),
      throwsArgumentError,
    );
    expect(
      () => settlement.recordPrintJob(sessionId: ' ', imageUrl: 'x'),
      throwsArgumentError,
    );
    expect(
      () => settlement.issueReceipt(sessionId: ' ', amount: 10),
      throwsArgumentError,
    );
  });

  test('issues an invoice number and pdf, then reuses it', () async {
    await settlement.recordApprovedPayment(
      paymentId: 'pay-1',
      sessionId: 'sess-1',
      amount: 250,
      paymentMode: 'COMPLIMENTARY',
    );
    final first = await settlement.issueReceipt(
      sessionId: 'sess-1',
      kioskCode: 'ODEON-01',
      amount: 250,
    );
    expect(first.receiptNumber, 'FZ/ODEON-01/2627/00001');
    expect(first.pdfPath, isNotNull);
    expect(first.json['pdfPath'], first.pdfPath);
    expect(first.json.containsKey('receiptPdfUrl'), isFalse);
    expect(first.json['paymentMode'], 'COMPLIMENTARY');
    final again = await settlement.issueReceipt(
      sessionId: 'sess-1',
      kioskCode: 'ODEON-01',
      amount: 999,
    );
    expect(again.receiptNumber, first.receiptNumber);
    expect(again.id, first.id);
  });

  test('defaults payment mode to cash when none recorded', () async {
    final issued = await settlement.issueReceipt(
      sessionId: 'sess-2',
      kioskCode: 'K1',
      amount: 10,
    );
    expect(issued.json['paymentMode'], 'CASH');
    expect(issued.receiptNumber, startsWith('FZ/'));
  });

  test('default clocks still issue a receipt', () async {
    final plain = LocalKioskSettlement(store: store);
    final issued = await plain.issueReceipt(
      sessionId: 'sess-3',
      amount: 1,
      paymentMode: 'UPI',
    );
    expect(issued.id, isNotEmpty);
    expect(issued.receiptNumber, startsWith('FZ/'));
  });

  test('pdf builder writes bytes', () async {
    final bytes = await buildLocalReceiptPdf(
      receiptNumber: 'FZ/K1/2627/00001',
      amount: -3,
      paymentMode: 'CASH',
      kioskCode: 'K1',
    );
    expect(bytes.length, greaterThan(40));
    final dated = await buildLocalReceiptPdf(
      receiptNumber: 'FZ/K1/2627/00002',
      amount: 10,
      paymentMode: 'UPI',
      kioskCode: 'K1',
      issuedAt: DateTime.utc(2026, 8, 23),
    );
    expect(dated, isNotEmpty);
  });

  test('settleApprovedPayment Fly success and cash WAN fallback', () async {
    final wan = await settleApprovedPayment(
      approveOnFly: () async {},
      store: store,
      paymentId: 'pay-fly',
      sessionId: 'sess-fly',
      paymentMode: 'CASH',
      amount: 100,
    );
    expect(wan, isFalse);
    expect((await store.paymentsForSession('sess-fly')), hasLength(1));

    final offline = await settleApprovedPayment(
      approveOnFly: () async => throw ApiException('Network error occurred'),
      store: store,
      paymentId: 'pay-off',
      sessionId: 'sess-off',
      paymentMode: 'COMPLIMENTARY',
      amount: 0,
    );
    expect(offline, isTrue);

    await expectLater(
      settleApprovedPayment(
        approveOnFly: () async => throw ApiException('nope', 400),
        store: store,
        paymentId: 'pay-bad',
        sessionId: 'sess-bad',
        paymentMode: 'CASH',
        amount: 1,
      ),
      throwsA(isA<ApiException>()),
    );

    await expectLater(
      settleApprovedPayment(
        approveOnFly: () async => throw ApiException('down'),
        store: store,
        paymentId: 'pay-upi',
        sessionId: 'sess-upi',
        paymentMode: 'UPI',
        amount: 1,
      ),
      throwsA(isA<ApiException>()),
    );

    final timedOut = await settleApprovedPayment(
      approveOnFly: () async => throw TimeoutException('t'),
      store: store,
      paymentId: 'pay-to',
      sessionId: 'sess-to',
      paymentMode: 'CASH',
      amount: 10,
    );
    expect(timedOut, isTrue);

    await expectLater(
      settleApprovedPayment(
        approveOnFly: () async => throw ApiException('down'),
        store: store,
        paymentId: 'pay-wire',
        sessionId: 'sess-wire',
        paymentMode: 'WIRE',
        amount: 1,
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('issueReceipt uses latest parseable payment mode', () async {
    await store.upsertPayment(
      id: 'pay-bad',
      sessionId: 'sess-mode',
      payload: {'paymentMode': 'nope'},
    );
    await store.upsertPayment(
      id: 'pay-ok',
      sessionId: 'sess-mode',
      payload: {'paymentMode': 'UPI'},
    );
    final issued = await settlement.issueReceipt(
      sessionId: 'sess-mode',
      kioskCode: 'K1',
      amount: 10,
    );
    expect(issued.json['paymentMode'], 'UPI');
  });

  test('reuses a receipt when the number is only in payload', () async {
    await store.upsertReceipt(
      id: 'rc-p',
      sessionId: 'sess-p',
      receiptNumber: 'FZ/K1/2627/00009',
      payload: {'receiptNumber': 'FZ/K1/2627/00009'},
    );
    await store.closeForTest();
    final db = await LocalKioskDb.open(dir);
    expect(db, isNotNull);
    await db!.database.update(
      'receipts',
      {'receipt_number': null},
      where: 'id = ?',
      whereArgs: const ['rc-p'],
    );
    await db.close();

    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    final issued = await LocalKioskSettlement(store: reloaded).issueReceipt(
      sessionId: 'sess-p',
      amount: 1,
    );
    expect(issued.receiptNumber, 'FZ/K1/2627/00009');
    expect(issued.id, 'rc-p');
  });

  test('reuses a receipt with no stored number', () async {
    await store.upsertReceipt(
      id: 'rc-empty',
      sessionId: 'sess-empty',
      receiptNumber: 'FZ/K1/2627/00010',
      payload: <String, dynamic>{},
    );
    await store.closeForTest();
    final db = await LocalKioskDb.open(dir);
    expect(db, isNotNull);
    await db!.database.update(
      'receipts',
      {'receipt_number': null},
      where: 'id = ?',
      whereArgs: const ['rc-empty'],
    );
    await db.close();

    final reloaded = LocalKioskStore(resolveDirectory: () async => dir);
    final issued = await LocalKioskSettlement(store: reloaded).issueReceipt(
      sessionId: 'sess-empty',
      amount: 1,
    );
    expect(issued.receiptNumber, isEmpty);
    expect(issued.id, 'rc-empty');
  });
}
