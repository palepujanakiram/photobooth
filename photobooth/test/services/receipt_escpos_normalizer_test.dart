import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt/receipt_escpos_normalizer.dart';
import 'package:photobooth/services/receipt/receipt_printer_profile.dart';

void main() {
  group('ReceiptEscPosNormalizer', () {
    test('scales GS v 0 raster to 80mm width preserving aspect ratio', () {
      const sourceWidthBytes = 24; // 192 dots (~48mm)
      const sourceHeight = 100;
      final data = Uint8List(sourceWidthBytes * sourceHeight);
      for (var y = 0; y < sourceHeight; y++) {
        for (var x = 0; x < sourceWidthBytes; x++) {
          data[y * sourceWidthBytes + x] = x.isEven ? 0xFF : 0x00;
        }
      }

      final payload = Uint8List.fromList([
        0x1B, 0x40,
        0x1D, 0x76, 0x30, 0x00,
        sourceWidthBytes & 0xFF,
        (sourceWidthBytes >> 8) & 0xFF,
        sourceHeight & 0xFF,
        (sourceHeight >> 8) & 0xFF,
        ...data,
        0x0A,
      ]);

      final normalized = ReceiptEscPosNormalizer.normalize(payload);
      expect(normalized.length, greaterThan(payload.length));

      final gsIndex = normalized.indexOf(0x1D);
      expect(gsIndex, greaterThanOrEqualTo(0));
      expect(normalized[gsIndex + 1], 0x76);
      final widthBytes = normalized[gsIndex + 4] | (normalized[gsIndex + 5] << 8);
      expect(widthBytes * 8, ReceiptPrinterProfile.printWidthDots);

      final height = normalized[gsIndex + 6] | (normalized[gsIndex + 7] << 8);
      expect(height, greaterThan(sourceHeight));
    });

    test('leaves payload unchanged when no raster commands present', () {
      final payload = Uint8List.fromList([0x1B, 0x40, 0x48, 0x65, 0x6C, 0x6C, 0x6F]);
      final normalized = ReceiptEscPosNormalizer.normalize(payload);
      expect(normalized, payload);
    });

    test('returns payload unchanged when empty or target width invalid', () {
      expect(
        ReceiptEscPosNormalizer.normalize(Uint8List(0)),
        Uint8List(0),
      );
      final payload = Uint8List.fromList([0x1B, 0x40]);
      expect(
        ReceiptEscPosNormalizer.normalize(payload, targetWidthDots: 0),
        payload,
      );
    });

    test('scales ESC * raster segments to target width', () {
      const sourceWidthBytes = 12;
      const sourceHeight = 8;
      final data = Uint8List(sourceWidthBytes * sourceHeight);
      final payload = Uint8List.fromList([
        0x1B, 0x2A, 0x00,
        sourceWidthBytes & 0xFF,
        (sourceWidthBytes >> 8) & 0xFF,
        ...data,
      ]);

      final normalized = ReceiptEscPosNormalizer.normalize(payload);
      expect(normalized.length, greaterThan(payload.length));
      expect(normalized[0], 0x1B);
      expect(normalized[1], 0x2A);
    });

    test('scales GS v 0 double-width mode raster', () {
      const sourceWidthBytes = 24;
      const sourceHeight = 40;
      final data = Uint8List(sourceWidthBytes * sourceHeight);
      final payload = Uint8List.fromList([
        0x1D, 0x76, 0x30, 0x01,
        sourceWidthBytes & 0xFF,
        (sourceWidthBytes >> 8) & 0xFF,
        sourceHeight & 0xFF,
        (sourceHeight >> 8) & 0xFF,
        ...data,
      ]);
      final normalized = ReceiptEscPosNormalizer.normalize(payload);
      expect(normalized.length, greaterThan(payload.length));
    });

    test('leaves GS v 0 raster unchanged when already at target width', () {
      const sourceWidthBytes = ReceiptPrinterProfile.printWidthDots ~/ 8;
      const sourceHeight = 40;
      final data = Uint8List(sourceWidthBytes * sourceHeight);
      final payload = Uint8List.fromList([
        0x1D, 0x76, 0x30, 0x00,
        sourceWidthBytes & 0xFF,
        (sourceWidthBytes >> 8) & 0xFF,
        sourceHeight & 0xFF,
        (sourceHeight >> 8) & 0xFF,
        ...data,
      ]);
      final normalized = ReceiptEscPosNormalizer.normalize(payload);
      expect(normalized, payload);
    });

    test('escStarHeightForModeForTest returns zero for unknown modes', () {
      expect(escStarHeightForModeForTest(0x02), 0);
    });
  });
}
