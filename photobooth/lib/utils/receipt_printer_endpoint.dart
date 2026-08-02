import '../models/app_settings_model.dart';

/// Resolved LAN receipt printer target from `/api/settings`.
class ReceiptPrinterEndpoint {
  const ReceiptPrinterEndpoint({
    required this.host,
    required this.port,
  });

  static const defaultPort = 9100;

  final String host;
  final int port;

  bool get isConfigured => host.isNotEmpty;
}

ReceiptPrinterEndpoint resolveReceiptPrinterEndpoint(AppSettingsModel? settings) {
  final hostRaw = settings?.receiptPrinterHost?.trim();
  final host = (hostRaw != null && hostRaw.isNotEmpty) ? hostRaw : '';
  final portRaw = settings?.receiptPrinterPort;
  final port = (portRaw != null && portRaw > 0 && portRaw <= 65535)
      ? portRaw
      : ReceiptPrinterEndpoint.defaultPort;

  return ReceiptPrinterEndpoint(host: host, port: port);
}
