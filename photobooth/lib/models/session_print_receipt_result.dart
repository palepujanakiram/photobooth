import '../utils/json_parse_helpers.dart';

/// Response from `POST /api/sessions/:id/print-receipt` (or receipts/:id/print).
class SessionPrintReceiptResult {
  final bool success;
  final bool printerConfigured;
  final String? host;
  final int port;
  final String? payloadBase64;
  final bool deliveredByServer;
  final String? message;
  final String? error;
  final String? receiptId;
  final String? receiptNumber;

  const SessionPrintReceiptResult({
    required this.success,
    required this.printerConfigured,
    this.host,
    this.port = 9100,
    this.payloadBase64,
    this.deliveredByServer = false,
    this.message,
    this.error,
    this.receiptId,
    this.receiptNumber,
  });

  factory SessionPrintReceiptResult.fromJson(Map<String, dynamic> json) {
    final printer = json['printer'];
    String? host;
    int port = 9100;
    if (printer is Map) {
      host = JsonParseHelpers.stringOrNull(printer['host']);
      port = JsonParseHelpers.intOrNull(printer['port']) ?? 9100;
    }
    return SessionPrintReceiptResult(
      success: JsonParseHelpers.boolOrNull(json['success']) ?? false,
      printerConfigured:
          JsonParseHelpers.boolOrNull(json['printerConfigured']) ?? false,
      host: host,
      port: port,
      payloadBase64: JsonParseHelpers.stringOrNull(json['payloadBase64']),
      deliveredByServer:
          JsonParseHelpers.boolOrNull(json['deliveredByServer']) ?? false,
      message: JsonParseHelpers.stringOrNull(json['message']),
      error: JsonParseHelpers.stringOrNull(json['error']),
      receiptId: JsonParseHelpers.stringOrNull(json['receiptId']),
      receiptNumber: JsonParseHelpers.stringOrNull(json['receiptNumber']),
    );
  }

  /// True when the kiosk should open a LAN TCP socket and write [payloadBase64].
  bool get needsLanDelivery {
    if (deliveredByServer) return false;
    final h = host?.trim() ?? '';
    final p = payloadBase64?.trim() ?? '';
    return h.isNotEmpty && p.isNotEmpty;
  }
}
