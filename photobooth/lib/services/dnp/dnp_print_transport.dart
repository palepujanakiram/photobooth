import '../../models/app_settings_model.dart';
import '../../utils/app_config.dart';

/// How the kiosk reaches the DNP photo printer.
enum DnpPrintTransport {
  /// Android: USB first, then WCM Plus Wi-Fi discovery. iOS: Wi-Fi discovery.
  auto,

  /// Direct USB to DS-RX1(S)HS (Android only).
  usb,

  /// WCM Plus HTTP `/api/PrintImage` with subnet auto-discovery (no IP config).
  wifi,
}

/// Resolves transport from booth settings and compile-time overrides.
///
/// When settings omit [AppSettingsModel.printerTransport] (null / empty),
/// defaults to [DnpPrintTransport.wifi] (WCM Plus) so kiosks skip USB.
DnpPrintTransport resolveDnpPrintTransport(
  AppSettingsModel? settings, {
  String? transportOverride,
}) {
  final override =
      (transportOverride ?? AppConfig.printerTransportOverride).trim().toLowerCase();
  if (override.isNotEmpty) {
    return _parseTransportToken(override) ?? DnpPrintTransport.wifi;
  }

  final configured = settings?.printerTransport?.trim().toLowerCase() ?? '';
  if (configured.isNotEmpty) {
    return _parseTransportToken(configured) ?? DnpPrintTransport.wifi;
  }

  return DnpPrintTransport.wifi;
}

DnpPrintTransport? _parseTransportToken(String raw) {
  return switch (raw) {
    'auto' => DnpPrintTransport.auto,
    'usb' => DnpPrintTransport.usb,
    'wifi' || 'wcm' || 'wcm_plus' => DnpPrintTransport.wifi,
    _ => null,
  };
}
