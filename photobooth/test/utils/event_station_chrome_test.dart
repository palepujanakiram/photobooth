import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';
import 'package:photobooth/utils/event_station_chrome.dart';

void main() {
  EventInfoModel event({
    String code = 'GALA',
    String? name,
    String? tagline,
    EventSkinChrome skin = const EventSkinChrome(),
  }) {
    return EventInfoModel(
      id: 'e1',
      code: code,
      name: name,
      chrome: EventChrome(tagline: tagline, skin: skin),
    );
  }

  test('title prefers event name then booth code', () {
    expect(eventChromeTitle(event(name: ' Priya & Arjun ')), 'Priya & Arjun');
    expect(eventChromeTitle(event(name: '  ')), 'GALA');
    expect(eventChromeTitle(event()), 'GALA');
  });

  test('tagline prefers description then skin subtitle', () {
    expect(
      eventChromeTagline(event(tagline: 'Wedding celebration')),
      'Wedding celebration',
    );
    expect(
      eventChromeTaglineLabel(event(tagline: 'Wedding celebration')),
      'WEDDING CELEBRATION',
    );
    expect(
      eventChromeTagline(event(tagline: '  ')),
      'Warm peach to purple',
    );
    expect(
      eventChromeTagline(
        event(skin: const EventSkinChrome(subtitle: '  ')),
      ),
      '',
    );
    expect(
      eventChromeTagline(
        event(skin: const EventSkinChrome(subtitle: ' Deep blue ')),
      ),
      'Deep blue',
    );
  });

  test('banner and look colors parse hex with fallbacks', () {
    const navy = EventSkinChrome(
      bannerFrom: '1B3A5F',
      bannerTo: '#0E7490',
      ink: '#FFFFFF',
    );
    expect(eventChromeBannerFromArgb(navy), 0xFF1B3A5F);
    expect(eventChromeBannerToArgb(navy), 0xFF0E7490);
    expect(eventChromeInkArgb(navy), 0xFFFFFFFF);
    expect(eventChromeArgb('nope', 0xE3A65C), 0xFFE3A65C);
    expect(eventLookThemeArgb('#D97706'), 0xFFD97706);
    expect(eventLookThemeArgb('bad'), isNull);
    expect(
      eventLookFillArgb(themeHex: '#112233', skin: navy, index: 0),
      0xFF112233,
    );
    expect(
      eventLookFillArgb(themeHex: null, skin: navy, index: 0),
      0xFF1B3A5F,
    );
    expect(
      eventLookFillArgb(themeHex: '', skin: navy, index: 1),
      0xFF0E7490,
    );
  });
}
