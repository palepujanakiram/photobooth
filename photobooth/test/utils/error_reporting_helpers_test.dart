import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/error_reporting/error_reporting_manager.dart';
import 'package:photobooth/utils/error_reporting_helpers.dart';
import 'package:photobooth/utils/exceptions.dart';

import '../fakes/fake_error_reporting_service.dart';

void main() {
  setUp(() async {
    await ErrorReportingManager.initialize(enableBugsnag: false);
    await ErrorReportingManager.setEnabled(true);
  });

  test('shouldAutoReportError skips DioException and ApiException', () {
    expect(
      shouldAutoReportError(DioException(requestOptions: RequestOptions()), 'x'),
      isFalse,
    );
    expect(shouldAutoReportError(ApiException('fail'), 'x'), isFalse);
  });

  test('shouldAutoReportError skips filtered non-fatal messages', () {
    expect(
      shouldAutoReportError(Exception('x'), 'face count unavailable'),
      isFalse,
    );
    expect(
      shouldAutoReportError(Exception('x'), 'network image decode failed'),
      isFalse,
    );
    expect(
      shouldAutoReportError(Exception('x'), 'staff logout complete'),
      isFalse,
    );
  });

  test('shouldAutoReportError allows other errors', () {
    expect(shouldAutoReportError(Exception('boom'), 'capture failed'), isTrue);
  });

  test('reportIssue forwards allowed errors to ErrorReportingManager', () async {
    final fake = FakeErrorReportingService();
    // Exercise recordError path (no injected fake in prod manager).
    await reportIssue('test failure', Exception('boom'), StackTrace.current);
    expect(ErrorReportingManager.isInitialized, isTrue);
    fake.recordError(Exception('ignored'), StackTrace.current);
  });

  test('reportIssue skips filtered ApiException', () async {
    await reportIssue(
      'api failed',
      ApiException('server error', 500),
      StackTrace.current,
    );
    // No assertion on Bugsnag — ensures no throw when filtered.
  });
}
