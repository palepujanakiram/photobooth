import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/session_print_receipt_result.dart';
import 'package:photobooth/screens/staff/staff_payments_print_helpers.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  group('staffPaymentsIsReceiptPrinterConfigured', () {
    test('false when settings null or disabled', () {
      expect(staffPaymentsIsReceiptPrinterConfigured(null), isFalse);
      expect(
        staffPaymentsIsReceiptPrinterConfigured(
          AppSettingsModel(receiptPrinterEnabled: false, receiptPrinterHost: '10.0.0.1'),
        ),
        isFalse,
      );
    });

    test('false when enabled but host empty', () {
      expect(
        staffPaymentsIsReceiptPrinterConfigured(
          AppSettingsModel(receiptPrinterEnabled: true, receiptPrinterHost: '  '),
        ),
        isFalse,
      );
    });

    test('true when enabled with host', () {
      expect(
        staffPaymentsIsReceiptPrinterConfigured(
          AppSettingsModel(
            receiptPrinterEnabled: true,
            receiptPrinterHost: '192.168.1.50',
          ),
        ),
        isTrue,
      );
    });
  });

  group('staffPaymentsReceiptDeliverError', () {
    test('returns config/error message when not successful', () {
      expect(
        staffPaymentsReceiptDeliverError(
          const SessionPrintReceiptResult(
            success: false,
            printerConfigured: true,
            error: 'No receipt for session',
          ),
        ),
        'No receipt for session',
      );
      expect(
        staffPaymentsReceiptDeliverError(
          const SessionPrintReceiptResult(
            success: true,
            printerConfigured: false,
          ),
        ),
        AppStrings.receiptPrintNotConfigured,
      );
    });

    test('null when server already delivered', () {
      expect(
        staffPaymentsReceiptDeliverError(
          const SessionPrintReceiptResult(
            success: true,
            printerConfigured: true,
            deliveredByServer: true,
          ),
        ),
        isNull,
      );
    });

    test('empty payload when LAN delivery required but missing bytes', () {
      expect(
        staffPaymentsReceiptDeliverError(
          const SessionPrintReceiptResult(
            success: true,
            printerConfigured: true,
            host: '10.0.0.1',
            payloadBase64: '',
          ),
        ),
        AppStrings.receiptPrintEmptyPayload,
      );
    });

    test('null when LAN delivery payload is present', () {
      expect(
        staffPaymentsReceiptDeliverError(
          const SessionPrintReceiptResult(
            success: true,
            printerConfigured: true,
            host: '10.0.0.1',
            payloadBase64: 'YWJj',
          ),
        ),
        isNull,
      );
    });
  });
}
