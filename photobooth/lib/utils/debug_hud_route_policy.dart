import 'constants.dart';

/// Routes where the debug HUD must not cover consent / kiosk bootstrap UI.
const Set<String> _debugHudBlockedRoutes = {
  AppConstants.kRouteSplash,
  AppConstants.kRouteTerms,
};

/// Whether the on-screen debug HUD may appear on [routeName].
bool debugHudAllowedOnRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return true;
  return !_debugHudBlockedRoutes.contains(routeName);
}
