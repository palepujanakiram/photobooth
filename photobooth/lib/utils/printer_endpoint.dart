import '../models/app_settings_model.dart';
import 'constants.dart';

/// Resolved LAN printer HTTP target from `/api/settings`.
class PrinterEndpoint {
  const PrinterEndpoint({
    required this.host,
    required this.port,
    required this.path,
  });

  final String host;
  final int port;
  final String path;

  String get baseUrl {
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port == 80 ? null : port,
    );
    return uri.origin;
  }
}

/// Maps admin `printerPath` to the POST path the kiosk should use.
///
/// Matches zenai web kiosk: `/` or empty → `/api/PrintImage`; otherwise use
/// the configured path (e.g. `/print`).
String resolvePrinterApiPath(String? rawPath) {
  final raw = rawPath?.trim() ?? '';
  if (raw.isEmpty || raw == '/') {
    return '/api/PrintImage';
  }
  return raw.startsWith('/') ? raw : '/$raw';
}

PrinterEndpoint resolvePrinterEndpoint(AppSettingsModel? settings) {
  final hostRaw = settings?.printerHost?.trim();
  final host = (hostRaw != null && hostRaw.isNotEmpty)
      ? hostRaw
      : AppConstants.kDefaultPrinterHost;
  final portRaw = settings?.printerPort;
  final port = (portRaw != null && portRaw > 0 && portRaw <= 65535)
      ? portRaw
      : 80;
  return PrinterEndpoint(
    host: host,
    port: port,
    path: resolvePrinterApiPath(settings?.printerPath),
  );
}
