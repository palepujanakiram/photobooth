import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_payments_payload_utils.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('baseUrlNoTrailingSlash strips trailing slash', () {
    expect(
      StaffPaymentsPayloadUtils.baseUrlNoTrailingSlash(),
      isNot(endsWith('/')),
    );
    expect(
      StaffPaymentsPayloadUtils.baseUrlNoTrailingSlash(),
      AppConstants.kBaseUrl.endsWith('/')
          ? AppConstants.kBaseUrl.substring(0, AppConstants.kBaseUrl.length - 1)
          : AppConstants.kBaseUrl,
    );
  });

  test('looksLikeUrl recognizes relative and absolute paths', () {
    expect(StaffPaymentsPayloadUtils.looksLikeUrl(''), isFalse);
    expect(StaffPaymentsPayloadUtils.looksLikeUrl('https://x/a.jpg'), isTrue);
    expect(StaffPaymentsPayloadUtils.looksLikeUrl('/api/img/a.jpg'), isTrue);
    expect(StaffPaymentsPayloadUtils.looksLikeUrl('api/img/a.jpg'), isTrue);
    expect(StaffPaymentsPayloadUtils.looksLikeUrl('plain-text'), isFalse);
  });

  test('absolutizeIfRelative and normalizeImageUrl', () {
    expect(
      StaffPaymentsPayloadUtils.absolutizeIfRelative('/api/img/x.jpg'),
      contains('/api/img/x.jpg'),
    );
    expect(
      StaffPaymentsPayloadUtils.absolutizeIfRelative('api/img/x.jpg'),
      contains('api/img/x.jpg'),
    );
    expect(
      StaffPaymentsPayloadUtils.absolutizeIfRelative('https://cdn/x.jpg'),
      'https://cdn/x.jpg',
    );
    expect(
      StaffPaymentsPayloadUtils.absolutizeIfRelative('${AppStrings.dataImagePrefix}abc'),
      '${AppStrings.dataImagePrefix}abc',
    );

    final normalized = StaffPaymentsPayloadUtils.normalizeImageUrl(
      '/api/img/x.jpg',
      sessionId: 'sess-1',
    );
    expect(normalized, contains('sessionId=sess-1'));
  });

  test('deepFindFirstValueForKeys walks nested maps and lists', () {
    final found = StaffPaymentsPayloadUtils.deepFindFirstValueForKeys(
      {
        'nested': [
          {'session': {'id': '  sess-9  '}},
        ],
      },
      ['sessionId', 'session'],
    );
    expect(found, 'sess-9');

    expect(
      StaffPaymentsPayloadUtils.deepFindFirstValueForKeys({'a': 1}, ['missing']),
      isNull,
    );
    expect(
      StaffPaymentsPayloadUtils.deepFindFirstValueForKeys(null, ['id']),
      isNull,
    );
  });

  test('deepFindFirstUrl finds url fields and nested strings', () {
    expect(
      StaffPaymentsPayloadUtils.deepFindFirstUrl({
        'imageUrl': '/api/img/a.jpg',
      }),
      '/api/img/a.jpg',
    );
    expect(
      StaffPaymentsPayloadUtils.deepFindFirstUrl('https://x/y.png'),
      'https://x/y.png',
    );
    expect(
      StaffPaymentsPayloadUtils.deepFindFirstUrl({'items': [{'url': 'api/x'}]}),
      'api/x',
    );
    expect(StaffPaymentsPayloadUtils.deepFindFirstUrl({'n': 1}), isNull);
  });

  test('pickString returns first non-empty key', () {
    expect(
      StaffPaymentsPayloadUtils.pickString(
        {'status': '  ', 'id': 'pay-1'},
        ['status', 'id'],
      ),
      'pay-1',
    );
    expect(
      StaffPaymentsPayloadUtils.pickString({}, ['id']),
      '',
    );
  });

  test('imageUrlFromGeneratedEntry normalizes map and string entries', () {
    expect(
      StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry(
        {'imageUrl': '/api/img/a.jpg'},
        sessionId: 'sess-2',
      ),
      contains('sessionId=sess-2'),
    );
    expect(
      StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry('api/img/b.jpg'),
      isNotNull,
    );
    expect(
      StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry({'n': 1}),
      isNull,
    );
    expect(
      StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry('  '),
      isNull,
    );
  });

  test('resolveSessionImageUrl prefers generatedImages then deep search', () {
    expect(
      StaffPaymentsPayloadUtils.resolveSessionImageUrl(
        {
          'generatedImages': [
            {'imageUrl': '/api/img/from-list.jpg'},
          ],
        },
        sessionId: 'sess-3',
      ),
      contains('from-list.jpg'),
    );
    expect(
      StaffPaymentsPayloadUtils.resolveSessionImageUrl(
        {'nested': {'thumbnailUrl': '/api/img/deep.jpg'}},
        sessionId: 'sess-3',
      ),
      contains('deep.jpg'),
    );
    expect(
      StaffPaymentsPayloadUtils.resolveSessionImageUrl(
        {},
        sessionId: 'sess-3',
      ),
      isNull,
    );
  });

  test('userImageFieldFromSession reads user image fields', () {
    expect(
      StaffPaymentsPayloadUtils.userImageFieldFromSession({
        'userImageUrl': 'data:image/jpeg;base64,abc',
      }),
      'data:image/jpeg;base64,abc',
    );
    expect(
      StaffPaymentsPayloadUtils.userImageFieldFromSession({}),
      '',
    );
  });
}
