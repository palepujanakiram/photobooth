import 'constants.dart';

/// Station roles after kiosk + event bind. Transform is server-side only.
class EventStationRole {
  static const capture = 'capture';
  static const theme = 'theme';
  static const print = 'print';

  static const values = <String>[capture, theme, print];

  static bool isValid(String? role) =>
      role != null && values.contains(role);

  static String? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    return isValid(v) ? v : null;
  }
}

enum EventPostSplashRoute { terms, stationPicker, capture, theme, print }

/// After splash bind: event stations vs guest terms.
EventPostSplashRoute resolveEventPostSplashRoute({
  required String? eventCode,
  required String? stationRole,
}) {
  if (eventCode == null || eventCode.trim().isEmpty) {
    return EventPostSplashRoute.terms;
  }
  switch (EventStationRole.tryParse(stationRole)) {
    case EventStationRole.capture:
      return EventPostSplashRoute.capture;
    case EventStationRole.theme:
      return EventPostSplashRoute.theme;
    case EventStationRole.print:
      return EventPostSplashRoute.print;
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
    case EventPostSplashRoute.stationPicker:
      return AppConstants.kRouteEventStation;
    case EventPostSplashRoute.terms:
      return AppConstants.kRouteTerms;
  }
}

/// After photographer Continue: stay on capture station instead of theme pick.
String resolvePostCaptureRoute({required bool eventCaptureStation}) {
  return eventCaptureStation
      ? AppConstants.kRouteEventCaptureStation
      : AppConstants.kRouteHome;
}
