import 'constants.dart';

/// Station roles after kiosk + event bind. Transform is server-side only.
class EventStationRole {
  static const capture = 'capture';
  static const theme = 'theme';
  static const print = 'print';

  /// Local-first SD card import. Only offered when the event pipeline is on.
  static const sdImport = 'sd-import';

  static const values = <String>[capture, theme, print, sdImport];

  static bool isValid(String? role) => role != null && values.contains(role);

  static String? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    return isValid(v) ? v : null;
  }
}

enum EventPostSplashRoute {
  terms,
  stationPicker,
  capture,
  theme,
  print,
  sdImport,
  needsInternet,
}

/// Whether a station role still needs WAN to be usable.
///
/// Without the local pipeline every station is server-brokered: Capture creates
/// sessions, Theme polls the board, Print downloads job images. With it on, each
/// has local behaviour and an offline event boots straight to its station.
bool stationRequiresWan({
  required String? stationRole,
  required bool pipelineEnabled,
}) {
  final role = EventStationRole.tryParse(stationRole);
  if (role == null) return false;
  return !pipelineEnabled;
}

/// After splash bind: event stations vs guest terms.
///
/// [pipelineEnabled] defaults to false so the behaviour with the pipeline off is
/// byte-identical to before it existed — that is the regression guard.
EventPostSplashRoute resolveEventPostSplashRoute({
  required String? eventCode,
  required String? stationRole,
  bool wanAvailable = true,
  bool pipelineEnabled = false,
}) {
  if (eventCode == null || eventCode.trim().isEmpty) {
    return EventPostSplashRoute.terms;
  }
  final role = EventStationRole.tryParse(stationRole);
  if (!wanAvailable &&
      stationRequiresWan(
        stationRole: stationRole,
        pipelineEnabled: pipelineEnabled,
      )) {
    return EventPostSplashRoute.needsInternet;
  }
  switch (role) {
    case EventStationRole.capture:
      return EventPostSplashRoute.capture;
    case EventStationRole.theme:
      return EventPostSplashRoute.theme;
    case EventStationRole.print:
      return EventPostSplashRoute.print;
    case EventStationRole.sdImport:
      return EventPostSplashRoute.sdImport;
    default:
      return EventPostSplashRoute.stationPicker;
  }
}

String eventPostSplashRouteName(EventPostSplashRoute route) {
  switch (route) {
    case EventPostSplashRoute.capture:
      return AppConstants.kRouteEventCaptureStation;
    case EventPostSplashRoute.theme:
      return AppConstants.kRouteEventThemeStation;
    case EventPostSplashRoute.print:
      return AppConstants.kRouteEventPrintStation;
    case EventPostSplashRoute.sdImport:
      return AppConstants.kRouteEventIngestStation;
    case EventPostSplashRoute.stationPicker:
      return AppConstants.kRouteEventStation;
    case EventPostSplashRoute.terms:
      return AppConstants.kRouteTerms;
    case EventPostSplashRoute.needsInternet:
      return AppConstants.kRouteSplash;
  }
}

/// After photographer Continue: stay on capture station instead of theme pick.
String resolvePostCaptureRoute({required bool eventCaptureStation}) {
  return eventCaptureStation
      ? AppConstants.kRouteEventCaptureStation
      : AppConstants.kRouteHome;
}
