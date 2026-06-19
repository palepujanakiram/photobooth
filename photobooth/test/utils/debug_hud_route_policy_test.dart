import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/debug_hud_route_policy.dart';

void main() {
  test('debugHudAllowedOnRoute blocks bootstrap routes', () {
    expect(debugHudAllowedOnRoute(AppConstants.kRouteSplash), isFalse);
    expect(debugHudAllowedOnRoute(AppConstants.kRouteTerms), isFalse);
    expect(debugHudAllowedOnRoute(AppConstants.kRouteCapture), isTrue);
    expect(debugHudAllowedOnRoute(null), isTrue);
  });
}
