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
      },
    });
    expect(m.isValid, isTrue);
    expect(m.code, 'WED');
    expect(m.photoMode, 'FRAME_ONLY');
    expect(m.themeCount, 1);
    expect(m.frameCount, 4);
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
}
