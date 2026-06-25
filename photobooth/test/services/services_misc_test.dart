import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_logging/log_truncator.dart';
import 'package:photobooth/services/api_logging/payload_sanitizer.dart';
import 'package:photobooth/services/api_logging/web_api_log_summary.dart';
import 'package:photobooth/services/client_identification.dart';
import 'package:photobooth/services/error_reporting/error_reporting_manager.dart';
import 'package:photobooth/services/fcm_token_store.dart';
import 'package:photobooth/services/generation_display_preferences.dart';
import 'package:photobooth/services/share_service.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/web_flow_trace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogTruncator', () {
    const t = LogTruncator(maxLoggedJsonLength: 10);
    test('truncateJson adds marker when long', () {
      expect(t.truncateJson('12345678901'), contains('truncated'));
    });
    test('formatBytes and formatDuration', () {
      expect(t.formatBytes(2048), contains('KB'));
      expect(t.formatDuration(const Duration(milliseconds: 500)), contains('ms'));
      expect(t.formatDuration(const Duration(seconds: 65)), contains('m'));
    });
  });

  group('web api log summary', () {
    test('formatWebApiRequestSummary includes method', () {
      final s = formatWebApiRequestSummary(
        RequestOptions(path: '/api/themes', method: 'GET'),
      );
      expect(s, contains('GET'));
    });

    test('formatWebApiResponseSummary includes status', () {
      final s = formatWebApiResponseSummary(
        Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 200,
          data: [1, 2],
        ),
      );
      expect(s, contains('200'));
    });
  });

  test('ClientIdentification formatClientVersionLabel', () {
    expect(
      ClientIdentification.formatClientVersionLabel('2026.6.24'),
      '2026.06.24',
    );
    expect(
      ClientIdentification.formatClientVersionLabel('2026.5.100012'),
      '2026.05.10.0012',
    );
    expect(ClientIdentification.formatClientVersionLabel('0.1.0'), '0.1.0');
    expect(ClientIdentification.clientType, isNotEmpty);
    expect(ClientIdentification.platformLabel, isNotEmpty);
  });

  test('FcmTokenStore save and getCached', () async {
    SharedPreferences.setMockInitialValues({});
    await FcmTokenStore.save('  token-1  ');
    expect(await FcmTokenStore.getCached(), 'token-1');
    await FcmTokenStore.save('');
    expect(await FcmTokenStore.getCached(), 'token-1');
  });

  test('GenerationDisplayPreferences default true', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await GenerationDisplayPreferences.getUseProgressiveGenerationUi(), isTrue);
    await GenerationDisplayPreferences.setUseProgressiveGenerationUi(false);
    expect(await GenerationDisplayPreferences.getUseProgressiveGenerationUi(), isFalse);
  });

  test('ShareService rejects empty text', () async {
    expect(
      () => ShareService().shareText('  '),
      throwsA(isA<ShareException>()),
    );
  });

  test('ErrorReportingManager log when disabled', () async {
    await ErrorReportingManager.initialize(enableBugsnag: false);
    ErrorReportingManager.log('test breadcrumb');
    expect(ErrorReportingManager.isEnabled, isTrue);
  });

  test('WebFlowTrace reset and log in debug', () {
    WebFlowTrace.reset(label: 'test');
    WebFlowTrace.log('phase');
  });

  test('payload sanitizer masks auth and truncates data urls', () {
    const s = PayloadSanitizer();
    expect(s.maskAuthorization('Bearer abcdefghijklmnopqrst'), contains('...'));
    final out = s.sanitizeString(
      'data:image/jpeg;base64,${'x' * 300}',
    );
    expect(out, contains('omitted'));
  });
}
