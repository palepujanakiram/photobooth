import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/receipt_printer_config.dart';
import 'package:photobooth/utils/receipt_printer_endpoint.dart';

void main() {
  group('isReceiptPrinterEnabled', () {
    test('false when settings null or disabled', () {
      expect(isReceiptPrinterEnabled(null), isFalse);
      expect(
        isReceiptPrinterEnabled(AppSettingsModel(receiptPrinterEnabled: false)),
        isFalse,
      );
    });

    test('true when enabled without host (auto USB/Wi-Fi)', () {
      expect(
        isReceiptPrinterEnabled(AppSettingsModel(receiptPrinterEnabled: true)),
        isTrue,
      );
    });
  });

  group('resolveReceiptPrinterEndpoint', () {
    test('defaults port to 9100 when unset', () {
      final endpoint = resolveReceiptPrinterEndpoint(
        AppSettingsModel(receiptPrinterHost: '192.168.1.50'),
      );
      expect(endpoint.host, '192.168.1.50');
      expect(endpoint.port, ReceiptPrinterEndpoint.defaultPort);
      expect(endpoint.isConfigured, isTrue);
    });

    test('empty host is not configured', () {
      final endpoint = resolveReceiptPrinterEndpoint(
        AppSettingsModel(receiptPrinterEnabled: true, receiptPrinterHost: '  '),
      );
      expect(endpoint.isConfigured, isFalse);
    });
  });
}
