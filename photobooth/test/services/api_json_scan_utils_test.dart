import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_json_scan_utils.dart';

void main() {
  test('isJsonWhitespaceCodeUnit recognizes JSON whitespace', () {
    expect(ApiJsonScanUtils.isJsonWhitespaceCodeUnit(0x20), isTrue);
    expect(ApiJsonScanUtils.isJsonWhitespaceCodeUnit(0x09), isTrue);
    expect(ApiJsonScanUtils.isJsonWhitespaceCodeUnit(0x0a), isTrue);
    expect(ApiJsonScanUtils.isJsonWhitespaceCodeUnit(0x0d), isTrue);
    expect(ApiJsonScanUtils.isJsonWhitespaceCodeUnit(0x41), isFalse);
  });

  test('skipLeadingWhitespace advances past spaces', () {
    expect(ApiJsonScanUtils.skipLeadingWhitespace('  \t{"a":1}', 0), 3);
    expect(ApiJsonScanUtils.skipLeadingWhitespace('x', 0), 0);
  });

  test('indexOfLeadingCommaBefore finds comma or key index', () {
    const raw = '{"a":1,"b":2}';
    final bIndex = raw.indexOf('"b"');
    expect(ApiJsonScanUtils.indexOfLeadingCommaBefore(raw, bIndex), raw.indexOf(','));
    expect(ApiJsonScanUtils.indexOfLeadingCommaBefore('{"a":1}', 2), 2);
  });

  test('endIndexAfterJsonValue includes trailing comma', () {
    const withComma = '"x", "y"';
    final close = withComma.indexOf('"', 1);
    expect(
      ApiJsonScanUtils.endIndexAfterJsonValue(withComma, close),
      greaterThan(close),
    );
    const noComma = '"x" }';
    final close2 = noComma.indexOf('"', 1);
    expect(ApiJsonScanUtils.endIndexAfterJsonValue(noComma, close2), close2 + 2);
  });
}
