import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled terms asset is registered and non-empty', () async {
    expect(
      AppConstants.kTermsAndConditionsAssetPath,
      'assets/legal/terms.html',
    );
    final html =
        await rootBundle.loadString(AppConstants.kTermsAndConditionsAssetPath);
    expect(html, contains('Terms'));
    expect(html, contains('FotoZen'));
    expect(html, contains('Privacy Protection'));
    expect(html, contains('background: #ffffff'));
    expect(html, isNot(contains('prefers-color-scheme: dark')));
  });
}
