import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/capture_flow_log.dart';
import 'package:photobooth/utils/logger.dart';

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

  group('CaptureFlowLog.event', () {
    test('covers private constructor and all log levels', () {
      CaptureFlowLog.touchPrivateConstructorForTests();
      CaptureFlowLog.event('capture.debug', level: LogLevel.debug);
      CaptureFlowLog.event('capture.info', fields: {'k': 'v'});
      CaptureFlowLog.event('capture.warn', level: LogLevel.warning);
      CaptureFlowLog.event('capture.err', level: LogLevel.error);
      CaptureFlowLog.event(
        'capture.web',
        fields: {'shot': 1},
        webFlow: true,
      );
    });
  });
}
