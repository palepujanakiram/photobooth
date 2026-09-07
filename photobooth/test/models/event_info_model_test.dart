import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_info_model.dart';

void main() {
  test('fromJson reads nested event payload', () {
    final m = EventInfoModel.fromJson({
      'success': true,
      'event': {
        'id': 'e1',
        'code': 'WED',
        'name': 'Wedding',
        'photoMode': 'FRAME_ONLY',
        'currentlyActive': true,
        'themeCount': 1,
        'frameCount': 4,
        'themeIds': ['t1', '', '  '],
        'frameIds': ['f1'],
      },
    });
    expect(m.isValid, isTrue);
    expect(m.code, 'WED');
    expect(m.photoMode, 'FRAME_ONLY');
    expect(m.themeCount, 1);
    expect(m.frameCount, 4);
    expect(m.themeIds, ['t1']);
    expect(m.frameIds, ['f1']);
    expect(m.outputMode, 'BOTH');
  });

  test('fromJson reads flat payload', () {
    final m = EventInfoModel.fromJson({
      'id': 'e2',
      'code': 'GALA',
      'photo_mode': 'BOTH',
    });
    expect(m.id, 'e2');
    expect(m.photoMode, 'BOTH');
  });

  test('fromJson maps inactive flags and numeric strings', () {
    final inactive = EventInfoModel.fromJson({
      'id': 'e3',
      'code': 'OFF',
      'currentlyActive': false,
      'theme_count': '2',
      'frame_count': 4.0,
    });
    expect(inactive.currentlyActive, isFalse);
    expect(inactive.themeCount, 2);
    expect(inactive.frameCount, 4);

    final byIsActive = EventInfoModel.fromJson({
      'id': 'e4',
      'code': 'OFF2',
      'isActive': false,
    });
    expect(byIsActive.currentlyActive, isFalse);
    expect(byIsActive.isValid, isTrue);

    final junkCounts = EventInfoModel.fromJson({
      'id': 'e5',
      'code': 'JUNK',
      'theme_count': true,
      'frame_count': 'nope',
    });
    expect(junkCounts.themeCount, 0);
    expect(junkCounts.frameCount, 0);
  });

  test('isValid requires id and code', () {
    expect(
      EventInfoModel.fromJson({'id': '', 'code': 'X'}).isValid,
      isFalse,
    );
    expect(
      EventInfoModel.fromJson({'id': 'e', 'code': ''}).isValid,
      isFalse,
    );
  });

  test('fromJson reads output mode and skin chrome', () {
    final m = EventInfoModel.fromJson({
      'id': 'e6',
      'code': 'GALA',
      'outputMode': 'DIGITAL_ONLY',
      'description': 'Launch night',
      'skin': {
        'id': 'corporate-navy',
        'name': 'Corporate navy',
        'subtitle': 'Deep blue, clean type',
        'bannerFrom': '1B3A5F',
        'bannerTo': '#0E7490',
        'ink': '#FFFFFF',
      },
    });
    expect(m.outputMode, 'DIGITAL_ONLY');
    expect(m.chrome.skin.id, 'corporate-navy');
    expect(m.chrome.skin.bannerFrom, '#1B3A5F');
    expect(m.chrome.skin.subtitle, 'Deep blue, clean type');
    expect(m.description, 'Launch night');
    expect(m.toJson()['skin'], isA<Map>());
    expect(m.toJson()['description'], 'Launch night');

    final fallback = EventInfoModel.fromJson({
      'id': 'e7',
      'code': 'X',
      'output_mode': 'nope',
    });
    expect(fallback.outputMode, 'BOTH');
    expect(fallback.chrome.skin.id, 'wedding-gold');

    final emptySkin = EventSkinChrome.fromJson({
      'id': '  ',
      'name': '',
      'bannerFrom': '',
      'banner_to': '',
      'ink': '',
    });
    expect(emptySkin.id, 'wedding-gold');
    expect(emptySkin.name, 'Wedding gold');
    expect(emptySkin.bannerFrom, '#E3A65C');
    expect(emptySkin.subtitle, 'Warm peach to purple');

    final printOnly = EventChrome.fromJson({
      'outputMode': 'PHYSICAL_PRINT',
      'skin': 'not-a-map',
    });
    expect(printOnly.outputMode, 'PHYSICAL_PRINT');
    expect(printOnly.skin.id, 'wedding-gold');

    final tagged = EventChrome.fromJson({
      'tagline': 'Garden party',
      'outputMode': 'BOTH',
    });
    expect(tagged.tagline, 'Garden party');
    expect(EventChrome.fromJson({'description': '  '}).tagline, isNull);
  });

  test('fromCache requires a matching valid event map', () {
    expect(EventInfoModel.fromCache('nope', expectedCode: 'GALA'), isNull);
    expect(EventInfoModel.fromCache({'id': '', 'code': 'GALA'}, expectedCode: 'GALA'), isNull);
    expect(
      EventInfoModel.fromCache(
        {'id': 'e1', 'code': 'PARTY'},
        expectedCode: 'GALA',
      ),
      isNull,
    );
    final ok = EventInfoModel.fromCache(
      {
        'id': 'e1',
        'code': 'gala-01',
        'name': 'Priya & Arjun',
        'skin': {'id': 'wedding-gold'},
      },
      expectedCode: 'GALA-01',
    );
    expect(ok?.name, 'Priya & Arjun');
    expect(ok?.chrome.skin.id, 'wedding-gold');
  });

  test('parseRgbHex reads 6-digit colors', () {
    expect(parseRgbHex('#E3A65C'), 0xE3A65C);
    expect(parseRgbHex('0E7490'), 0x0E7490);
    expect(parseRgbHex('xyz'), isNull);
    expect(parseRgbHex('#fff'), isNull);
    expect(parseRgbHex(''), isNull);
  });
}
