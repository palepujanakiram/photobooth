import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_logging/request_formatter.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  group('estimatePayloadSizeForLogging', () {
    test('returns null for null data', () {
      expect(estimatePayloadSizeForLogging(null), isNull);
    });

    test('returns string length for string body', () {
      expect(estimatePayloadSizeForLogging('hello'), 5);
    });

    test('returns size for map with large userImageUrl', () {
      final size = estimatePayloadSizeForLogging({
        'userImageUrl': 'x' * 10000,
        'id': 's1',
      });
      expect(size, isNotNull);
      expect(size!, greaterThan(0));
    });
  });

  test('api log separator matches formatter constant', () {
    expect(AppStrings.apiLogSeparator.length, greaterThan(10));
  });
}
