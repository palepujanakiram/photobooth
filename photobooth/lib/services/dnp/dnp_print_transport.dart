import '../../models/app_settings_model.dart';
import '../../utils/app_config.dart';
import '../../utils/printer_endpoint.dart';

/// How the kiosk reaches the DNP photo printer.
enum DnpPrintTransport {
  /// **Default when no kiosk printer IP:** Android tries USB when a DS-RX1 is
  /// connected, otherwise discovers WCM Plus on the local Wi-Fi subnet.
  /// iOS uses Wi-Fi discovery only.
  auto,

  /// Direct USB to DS-RX1(S)HS (Android only); no Wi-Fi fallback.
  usb,

  /// WCM Plus HTTP `/api/PrintImage`. Uses kiosk `printerHost` when set;
  /// otherwise subnet auto-discovery.
  wifi,
}

/// Resolves transport from booth settings and compile-time overrides.
///
/// Precedence:
/// 1. `--dart-define=PRINTER_TRANSPORT=…` / [transportOverride]
/// 2. Kiosk [AppSettingsModel.printerHost] → [DnpPrintTransport.wifi] (skip auto/USB)
/// 3. Explicit [AppSettingsModel.printerTransport]
/// 4. [DnpPrintTransport.auto]
DnpPrintTransport resolveDnpPrintTransport(
  AppSettingsModel? settings, {
  String? transportOverride,
}) {
  final override =
      (transportOverride ?? AppConfig.printerTransportOverride).trim().toLowerCase();
  if (override.isNotEmpty) {
    return _parseTransportToken(override) ?? DnpPrintTransport.auto;
  }

  // Admin-configured LAN IP wins over auto/USB so the booth always hits that
  // printer (no USB probe, no subnet discovery).
  if (hasConfiguredPrinterHost(settings)) {
    return DnpPrintTransport.wifi;
  }

  final configured = settings?.printerTransport?.trim().toLowerCase() ?? '';
  if (configured.isNotEmpty) {
    return _parseTransportToken(configured) ?? DnpPrintTransport.auto;
  }

  return DnpPrintTransport.auto;
}

DnpPrintTransport? _parseTransportToken(String raw) {
  return switch (raw) {
    'auto' => DnpPrintTransport.auto,
    'usb' => DnpPrintTransport.usb,
    'wifi' || 'wcm' || 'wcm_plus' => DnpPrintTransport.wifi,
    _ => null,
  };
}
