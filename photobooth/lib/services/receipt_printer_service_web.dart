import '../utils/app_strings.dart';
import '../utils/exceptions.dart';

/// Web: raw TCP to LAN printers is unavailable in the browser.
class ReceiptPrinterService {
  ReceiptPrinterService({
    this.connectTimeout = const Duration(seconds: 5),
  });

  final Duration connectTimeout;

  Future<void> sendEscPosBase64({
    required String host,
    required int port,
    required String payloadBase64,
  }) async {
    throw ApiException(AppStrings.receiptPrintUnsupportedOnWeb);
  }

  Future<void> sendEscPosBytes({
    required String host,
    required int port,
    required List<int> bytes,
  }) async {
    throw ApiException(AppStrings.receiptPrintUnsupportedOnWeb);
  }
}
