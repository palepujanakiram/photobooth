import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/event_station_role.dart';

void main() {
  test('tryParse accepts known roles', () {
    expect(EventStationRole.tryParse(' Capture '), EventStationRole.capture);
    expect(EventStationRole.tryParse('THEME'), EventStationRole.theme);
    expect(EventStationRole.tryParse('print'), EventStationRole.print);
    expect(EventStationRole.tryParse('nope'), isNull);
    expect(EventStationRole.tryParse(''), isNull);
    expect(EventStationRole.isValid(EventStationRole.capture), isTrue);
  });

  test('post-splash route is terms without an event', () {
    expect(
      resolveEventPostSplashRoute(eventCode: null, stationRole: 'capture'),
      EventPostSplashRoute.terms,
    );
    expect(
      eventPostSplashRouteName(EventPostSplashRoute.terms),
      AppConstants.kRouteTerms,
    );
  });

  test('post-splash route uses saved station role', () {
    expect(
      resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'capture'),
      EventPostSplashRoute.capture,
    );
    expect(
      resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'theme'),
      EventPostSplashRoute.theme,
    );
    expect(
      resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: 'print'),
      EventPostSplashRoute.print,
    );
    expect(
      resolveEventPostSplashRoute(eventCode: 'GALA', stationRole: null),
      EventPostSplashRoute.stationPicker,
    );
    expect(
      eventPostSplashRouteName(EventPostSplashRoute.stationPicker),
      AppConstants.kRouteEventStation,
    );
    expect(
      eventPostSplashRouteName(EventPostSplashRoute.capture),
      AppConstants.kRouteEventCaptureStation,
    );
    expect(
      eventPostSplashRouteName(EventPostSplashRoute.theme),
      AppConstants.kRouteEventThemeStation,
    );
    expect(
      eventPostSplashRouteName(EventPostSplashRoute.print),
      AppConstants.kRouteEventPrintStation,
    );
  });

  test('WAN-down station role never enters guest Classic', () {
    for (final role in EventStationRole.values) {
      expect(
        resolveEventPostSplashRoute(
          eventCode: 'GALA',
          stationRole: role,
          wanAvailable: false,
        ),
        EventPostSplashRoute.needsInternet,
      );
    }
    expect(
      resolveEventPostSplashRoute(
        eventCode: 'GALA',
        stationRole: null,
        wanAvailable: false,
      ),
      EventPostSplashRoute.stationPicker,
    );
  });

  test('post-capture route stays on capture station in event mode', () {
    expect(
      resolvePostCaptureRoute(eventCaptureStation: true),
      AppConstants.kRouteEventCaptureStation,
    );
    expect(
      resolvePostCaptureRoute(eventCaptureStation: false),
      AppConstants.kRouteHome,
    );
  });
}
