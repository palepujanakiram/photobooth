import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/staff_api_session_helpers.dart';

void main() {
  test('parseSessionResponse accepts top-level session with matching id', () {
    final parsed = StaffApiSessionHelpers.parseSessionResponse(
      {
        'id': 'sess-1',
        'generatedImages': [
          {'imageUrl': '/api/img/a.jpg'},
        ],
      },
      expectedSessionId: 'sess-1',
    );
    expect(parsed?['id'], 'sess-1');
  });

  test('parseSessionResponse unwraps nested session object', () {
    final parsed = StaffApiSessionHelpers.parseSessionResponse(
      {
        'session': {
          'id': 'sess-2',
          'latestImageUrl': '/api/img/b.jpg',
        },
      },
      expectedSessionId: 'sess-2',
    );
    expect(parsed?['latestImageUrl'], '/api/img/b.jpg');
  });

  test('parseSessionResponse rejects API error payloads', () {
    expect(
      StaffApiSessionHelpers.parseSessionResponse(
        {'error': 'No active kiosk session'},
        expectedSessionId: 'sess-3',
      ),
      isNull,
    );
  });

  test('parseSessionResponse rejects mismatched session id', () {
    expect(
      StaffApiSessionHelpers.parseSessionResponse(
        {'id': 'other', 'generatedImages': []},
        expectedSessionId: 'sess-4',
      ),
      isNull,
    );
  });

  test('hasImageHints detects generatedImages without id', () {
    expect(
      StaffApiSessionHelpers.hasImageHints({
        'generatedImages': [
          {'imageUrl': '/api/img/c.jpg'},
        ],
      }),
      isTrue,
    );
  });
}
