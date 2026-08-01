import '../../models/app_settings_model.dart';
import '../../utils/app_config.dart';

/// How the kiosk reaches the DNP photo printer.
enum DnpPrintTransport {
  /// **Default kiosk policy:** Android tries USB when a DS-RX1 is connected,
  /// otherwise discovers WCM Plus on the local Wi-Fi subnet (no IP config).
  /// iOS uses Wi-Fi discovery only.
  auto,

  /// Direct USB to DS-RX1(S)HS (Android only); no Wi-Fi fallback.
  usb,

  /// WCM Plus HTTP `/api/PrintImage` with subnet auto-discovery only.
  wifi,
}

/// Resolves transport from booth settings and compile-time overrides.
///
/// When settings omit [AppSettingsModel.printerTransport] (null / empty),
/// defaults to [DnpPrintTransport.auto] (USB first on Android, then WCM Wi-Fi).
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
