import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  test('shared user-facing strings are non-empty', () {
    expect(AppStrings.printJobSentSuccess, isNotEmpty);
    expect(AppStrings.failedToFetch, isNotEmpty);
    expect(AppStrings.unknownNetworkError, isNotEmpty);
    expect(AppStrings.imageFileEmpty, isNotEmpty);
    expect(AppStrings.cameraLabelExternal, isNotEmpty);
    expect(AppStrings.cameraLabelBuiltIn, isNotEmpty);
    expect(AppStrings.apiLogSeparator, isNotEmpty);
  });
}
