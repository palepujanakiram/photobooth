import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_session_patch_json.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('jsonStringCloseQuoteIndex handles escapes', () {
    expect(jsonStringCloseQuoteIndex(r'"a\"b"', 0), 5);
    expect(jsonStringCloseQuoteIndex(r'"\u0041"', 0), 7);
    expect(jsonStringCloseQuoteIndex('"open', 0), -1);
  });

  test('stripEchoedUserImageUrlField removes large echoed field', () {
    final huge = 'x' * 200;
    final raw =
        '{"sessionId":"s","userImageUrl":"$huge","selectedThemeId":"t1"}';
    final slim = stripEchoedUserImageUrlField(raw);
    expect(slim, isNot(contains('userImageUrl')));
    expect(slim, contains('selectedThemeId'));
  });

  test('stripEchoedUserImageUrlField fast-strips large data URLs', () {
    final b64 = 'A' * 50000;
    final raw =
        '{"id":"s","userImageUrl":"data:image/jpeg;base64,$b64","personCount":1}';
    final slim = stripEchoedUserImageUrlField(raw);
    expect(slim, isNot(contains('userImageUrl')));
    expect(slim, contains('"personCount":1'));
  });

  test('assertSessionBodyLooksLikeJson rejects HTML', () {
    expect(
      () => assertSessionBodyLooksLikeJson('<html>', 'PATCH'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => assertSessionBodyLooksLikeJson('<!DOCTYPE html>', 'PATCH'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => assertSessionBodyLooksLikeJson('not-json', 'PATCH'),
      throwsA(isA<ApiException>()),
    );
  });

  test('parseSessionPatchResponseJson strips userImageUrl', () {
    final map = parseSessionPatchResponseJson(
      '{"sessionId":"s","userImageUrl":"data:image/jpeg;base64,abc","selectedThemeId":"t"}',
    );
    expect(map['sessionId'], 's');
    expect(map.containsKey('userImageUrl'), isFalse);
    expect(map['selectedThemeId'], 't');
  });

  test('parseSessionPatchResponseJson fallback when strip fails', () {
    final map = parseSessionPatchResponseJson('{"sessionId":"s","n":1}');
    expect(map['sessionId'], 's');
  });

  test('stripEchoedUserImageUrlField keeps json when value quote missing', () {
    const raw = '{"sessionId":"s","userImageUrl":broken}';
    expect(stripEchoedUserImageUrlField(raw), raw);
  });

  test('stripEchoedUserImageUrlField removes comma-prefixed key', () {
    final huge = 'z' * 50;
    final raw = '{"sessionId":"s", "userImageUrl":"$huge","n":1}';
    final slim = stripEchoedUserImageUrlField(raw);
    expect(slim, isNot(contains('userImageUrl')));
    expect(slim, contains('"n":1'));
  });

  test('assertSessionBodyLooksLikeJson rejects doctype', () {
    expect(
      () => assertSessionBodyLooksLikeJson('<!DOCTYPE html><body></body>', 'PATCH'),
      throwsA(isA<ApiException>()),
    );
  });

  test('parseSessionPatchResponseJson uses fallback parse path', () {
    final map = parseSessionPatchResponseJson(
      '{"sessionId":"s","userImageUrl":"data:image/jpeg;base64,abc","x":1}',
    );
    expect(map['sessionId'], 's');
    expect(map.containsKey('userImageUrl'), isFalse);
  });

  test('parseSessionPatchResponseJson throws on invalid JSON', () {
    expect(
      () => parseSessionPatchResponseJson('not json at all'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => parseSessionPatchResponseJson('[]'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => parseSessionPatchResponseJson('{bad json'),
      throwsA(isA<ApiException>()),
    );
  });

  test('stripEchoedUserImageUrlField returns raw when colon missing', () {
    expect(stripEchoedUserImageUrlField('{"userImageUrl" "x"}'), contains('userImageUrl'));
  });

  test('stripEchoedUserImageUrlField handles trailing comma after value', () {
    expect(stripEchoedUserImageUrlField('{"userImageUrl":"ab","id":1}'), '{"id":1}');
    expect(stripEchoedUserImageUrlField('{"userImageUrl":"ab",}'), '{}');
    expect(stripEchoedUserImageUrlField('{"userImageUrl":"ab" ,"id":1}'), '{"id":1}');
  });

  test('assertSessionBodyLooksLikeJson rejects generic angle bracket markup', () {
    expect(
      () => assertSessionBodyLooksLikeJson('<span>not json</span>', 'PATCH'),
      throwsA(isA<ApiException>()),
    );
  });

  test('stripEchoedUserImageUrlField skips when no opening quote', () {
    expect(
      stripEchoedUserImageUrlField('{"userImageUrl":   , "id":"s"}'),
      contains('userImageUrl'),
    );
  });
}
