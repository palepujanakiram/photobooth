import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/android_process_exit.dart';

void main() {
  test('tryParse rejects non-maps and incomplete rows', () {
    expect(AndroidProcessExit.tryParse(null), isNull);
    expect(AndroidProcessExit.tryParse('x'), isNull);
    expect(AndroidProcessExit.tryParse(<String, Object?>{}), isNull);
    expect(
      AndroidProcessExit.tryParse(<String, Object?>{'timestampMs': 0, 'reason': 'CRASH'}),
      isNull,
    );
    expect(
      AndroidProcessExit.tryParse(<String, Object?>{'timestampMs': 1, 'reason': '  '}),
      isNull,
    );
  });

  test('tryParse and parseList map channel payloads', () {
    final parsed = AndroidProcessExit.tryParse(<Object, Object?>{
      'timestampMs': 1710000000000,
      'reason': 'LOW_MEMORY',
      'reasonCode': '3',
      'status': 9.0,
      'description': 'lmk',
      'importance': 100,
      'pssKb': 200,
      'rssKb': 300,
    });
    expect(parsed, isNotNull);
    expect(parsed!.isUnexpected, isTrue);
    expect(parsed.reasonCode, 3);
    expect(parsed.status, 9);
    expect(parsed.toJson()['reason'], 'LOW_MEMORY');
    expect(parsed.toExtraInfo()['android_exit_reason'], 'LOW_MEMORY');
    expect(parsed.occurredAt.isUtc, isTrue);

    expect(AndroidProcessExit.parseList(null), isEmpty);
    expect(
      AndroidProcessExit.parseList(<Object?>[
        parsed.toJson(),
        <String, Object?>{'timestampMs': 1},
      ]),
      hasLength(1),
    );
    expect(
      AndroidProcessExit.tryParse(<String, Object?>{
        'timestampMs': 5,
        'reason': 'CRASH',
        'reasonCode': 'nope',
      })!.reasonCode,
      isNull,
    );
  });

  test('expected self-exits are not treated as booth crashes', () {
    expect(isUnexpectedAndroidProcessReason('EXIT_SELF'), isFalse);
    expect(isUnexpectedAndroidProcessReason('USER_STOPPED'), isFalse);
    expect(isUnexpectedAndroidProcessReason('PACKAGE_UPDATED'), isFalse);
    expect(isUnexpectedAndroidProcessReason('anr'), isTrue);
    expect(isUnexpectedAndroidProcessReason('SIGNALED'), isTrue);
    expect(
      AndroidProcessExit(timestampMs: 8, reason: 'ANR').toJson(),
      {'timestampMs': 8, 'reason': 'ANR'},
    );
    expect(
      AndroidProcessExitException('ANR').toString(),
      'AndroidProcessExitException(ANR)',
    );
  });
}
