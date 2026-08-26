import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/services/local_invoice_sequence_hydrate.dart';
import 'package:photobooth/services/local_kiosk_store.dart';
import 'package:photobooth/utils/local_invoice_number.dart';

void main() {
  late Directory dir;
  late LocalKioskStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_inv_hydrate_');
    store = LocalKioskStore(resolveDirectory: () async => dir);
  });

  tearDown(() async {
    LocalKioskStore.resetInstance();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('hydrateLocalInvoiceSequenceFromKiosk raises counter', () async {
    await hydrateLocalInvoiceSequenceFromKiosk(
      kiosk: const KioskInfoModel(
        id: 'k1',
        code: 'MALL-01',
        invoiceLastSeq: 5,
      ),
      store: store,
    );
    final next = await store.allocateInvoiceNumber(kioskCode: 'MALL-01');
    expect(
      parseKioskInvoiceNumberParts(next)!.seq,
      6,
    );
  });

  test('hydrate no-ops without seq or store', () async {
    await hydrateLocalInvoiceSequenceFromKiosk(
      kiosk: const KioskInfoModel(id: 'k1', code: 'MALL-01'),
      store: store,
    );
    expect(
      parseKioskInvoiceNumberParts(
        await store.allocateInvoiceNumber(kioskCode: 'MALL-01'),
      )!
          .seq,
      1,
    );
  });
}
