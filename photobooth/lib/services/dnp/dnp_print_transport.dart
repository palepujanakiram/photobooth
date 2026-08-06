import '../../models/app_settings_model.dart';
import '../../utils/app_config.dart';

/// How the kiosk reaches the DNP photo printer.
enum DnpPrintTransport {
  /// Kiosk printer IP (if set) → USB (Android) → Wi‑Fi subnet discovery.
  auto,

  /// Direct USB to DS-RX1(S)HS (Android only); no Wi-Fi fallback.
  usb,

  /// WCM Plus HTTP `/api/PrintImage`: kiosk printer IP (if set) → discovery.
  wifi,
}

/// Resolves transport mode from booth settings and compile-time overrides.
///
/// **Mode precedence**
/// 1. `--dart-define=PRINTER_TRANSPORT=…` / [transportOverride]
/// 2. ZenAI kiosk [AppSettingsModel.printerTransport] (`auto` | `usb` | `wifi`)
/// 3. [DnpPrintTransport.auto]
///
/// **Hunt order inside each mode** (see [DnpPrintBridge]):
/// - `auto`: configured IP → USB → subnet discovery
/// - `usb`: USB only
/// - `wifi`: configured IP → subnet discovery
DnpPrintTransport resolveDnpPrintTransport(
  AppSettingsModel? settings, {
  String? transportOverride,
}) {
  final override =
      (transportOverride ?? AppConfig.printerTransportOverride).trim().toLowerCase();
  if (override.isNotEmpty) {
    return _parseTransportToken(override) ?? DnpPrintTransport.auto;
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
