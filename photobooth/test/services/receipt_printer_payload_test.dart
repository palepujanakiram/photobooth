import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/session_print_receipt_result.dart';
import 'package:photobooth/services/receipt_printer_payload.dart';

void main() {
  group('ReceiptPrinterPayload', () {
    test('decodes base64 payload', () {
      final encoded = base64Encode([0x1b, 0x40, 0x0a]);
      final bytes = ReceiptPrinterPayload.decodeBase64(encoded);
      expect(bytes, [0x1b, 0x40, 0x0a]);
    });

    test('rejects empty payload', () {
      expect(
        () => ReceiptPrinterPayload.decodeBase64('  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates host and port', () {
      expect(
        () => ReceiptPrinterPayload.validateHostPort(host: '', port: 9100),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ReceiptPrinterPayload.validateHostPort(
          host: '192.168.1.1',
          port: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      ReceiptPrinterPayload.validateHostPort(
        host: '192.168.2.43',
        port: 9100,
      );
    });
  });

  group('SessionPrintReceiptResult', () {
    test('parses printer and needsLanDelivery', () {
      final result = SessionPrintReceiptResult.fromJson({
        'success': true,
        'printerConfigured': true,
        'deliveredByServer': false,
        'payloadBase64': base64Encode([1, 2, 3]),
        'printer': {'host': '192.168.2.43', 'port': 9100, 'protocol': 'escpos-tcp'},
      });
      expect(result.needsLanDelivery, isTrue);
      expect(result.host, '192.168.2.43');
      expect(result.port, 9100);
    });

    test('skips LAN when server already delivered', () {
      final result = SessionPrintReceiptResult.fromJson({
        'success': true,
        'printerConfigured': true,
        'deliveredByServer': true,
        'payloadBase64': 'YQ==',
        'printer': {'host': '192.168.2.43', 'port': 9100},
      });
      expect(result.needsLanDelivery, isFalse);
    });
  });
}
