import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/capture_flow_log.dart';

void main() {
  group('CaptureFlowLog.formatFields', () {
    test('skips null and empty values', () {
      expect(
        CaptureFlowLog.formatFields({
          'a': 1,
          'b': null,
          'c': '',
          'd': '  ',
          'e': true,
        }),
        'a=1 e=true',
      );
    });

    test('returns empty for empty map', () {
      expect(CaptureFlowLog.formatFields(const {}), isEmpty);
    });
  });
}
