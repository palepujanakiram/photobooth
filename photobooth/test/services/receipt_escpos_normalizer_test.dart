import 'dart:typed_data';

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
  });
}
