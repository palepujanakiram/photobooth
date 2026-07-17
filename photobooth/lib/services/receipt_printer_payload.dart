import 'dart:convert';
import 'dart:typed_data';

/// Pure helpers for ESC/POS receipt delivery (unit-testable).
abstract final class ReceiptPrinterPayload {
  static Uint8List decodeBase64(String payloadBase64) {
    final trimmed = payloadBase64.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('payloadBase64 is empty');
    }
    return Uint8List.fromList(base64Decode(trimmed));
  }

  static void validateHostPort({required String host, required int port}) {
    final h = host.trim();
    if (h.isEmpty) {
      throw ArgumentError('host is empty');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('port out of range: $port');
    }
  }
}
