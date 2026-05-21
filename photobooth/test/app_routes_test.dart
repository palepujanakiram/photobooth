import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/app_routes.dart';
import 'package:photobooth/screens/splash/bootstrap_route_args.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('buildAppRoutes registers core route names', () {
    final routes = buildAppRoutes();
    expect(routes.keys, contains(AppConstants.kRouteHome));
    expect(routes.keys, contains(AppConstants.kRouteCapture));
    expect(routes.keys, contains(AppConstants.kRouteTerms));
    expect(routes[AppConstants.kRouteSplash], isNotNull);
  });

  test('SplashRouteArgs manageKiosk flag', () {
    expect(const SplashRouteArgs(manageKiosk: true).manageKiosk, isTrue);
    expect(const TermsRouteArgs(backgroundImageUrls: ['a']).backgroundImageUrls, ['a']);
  });
}
