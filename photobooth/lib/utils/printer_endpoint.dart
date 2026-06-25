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
/// `/` or empty → `/api/PrintImage` (DNP HTTP API).
///
/// WCM Plus also serves a **guest web UI** at `/print`; that URL is not a print
/// API and returns HTTP 500 on POST. The working HTTP endpoint on WCM is
/// `/api/PrintImage` (multipart). Admin often sets `printerPath` to `/print`
/// when meaning `wcmPlusPath` — remap that here so kiosks still print.
String resolvePrinterApiPath(String? rawPath) {
  final raw = rawPath?.trim() ?? '';
  if (raw.isEmpty || raw == '/') {
    return '/api/PrintImage';
  }
  final normalized = raw.startsWith('/') ? raw : '/$raw';
  if (normalized == '/print') {
    return '/api/PrintImage';
  }
  return normalized;
}

/// DNP HTTP API at `/api/PrintImage` expects multipart form fields.
bool usesDnpMultipartPrintApi(String apiPath) {
  return apiPath.trim().toLowerCase() == '/api/printimage';
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
