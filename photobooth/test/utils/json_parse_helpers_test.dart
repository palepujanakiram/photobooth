import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/json_parse_helpers.dart';

void main() {
  test('stringValue coerces null and numbers', () {
    expect(JsonParseHelpers.stringValue(null), '');
    expect(JsonParseHelpers.stringValue(42), '42');
    expect(JsonParseHelpers.stringValue('x'), 'x');
  });

  test('intOrNull accepts num', () {
    expect(JsonParseHelpers.intOrNull(3), 3);
    expect(JsonParseHelpers.intOrNull(3.7), 4);
    expect(JsonParseHelpers.intOrNull('x'), isNull);
  });

  test('dateTimeOrNull rejects invalid strings', () {
    expect(
      JsonParseHelpers.dateTimeOrNull('2026-01-01T00:00:00.000Z'),
      isNotNull,
    );
    expect(JsonParseHelpers.dateTimeOrNull('not-a-date'), isNull);
    expect(JsonParseHelpers.dateTimeOrNull(null), isNull);
  });
}
