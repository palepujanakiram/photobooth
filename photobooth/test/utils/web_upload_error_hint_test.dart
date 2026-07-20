import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/web_upload_error_hint.dart';

void main() {
  test('webUploadErrorHint returns empty off web', () {
    expect(webUploadErrorHint(), '');
    expect(
      webUploadErrorHintImpl(
        isWeb: false,
        baseUrl: 'http://localhost:8080',
        apiError: ApiException('denied', 403),
      ),
      '',
    );
  });

  test('webUploadErrorHintImpl suggests proxy on localhost web', () {
    expect(
      webUploadErrorHintImpl(
        isWeb: true,
        baseUrl: 'http://localhost:8080',
      ),
      contains('run_web_dev.sh'),
    );
    expect(
      webUploadErrorHintImpl(
        isWeb: true,
        baseUrl: 'http://127.0.0.1:5000',
      ),
      isNotEmpty,
    );
  });

  test('webUploadErrorHintImpl mentions expired session on 403', () {
    expect(
      webUploadErrorHintImpl(
        isWeb: true,
        baseUrl: 'https://fotozenai.fly.dev',
        apiError: ApiException('forbidden', 403),
      ),
      contains('session may have expired'),
    );
  });

  test('webUploadErrorHintImpl empty for production web without 403', () {
    expect(
      webUploadErrorHintImpl(
        isWeb: true,
        baseUrl: 'https://fotozenai.fly.dev',
      ),
      '',
    );
  });
}
