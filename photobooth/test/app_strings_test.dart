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

  test('interpolated string methods return expected values', () {
    expect(AppStrings.generationWaitActiveStepLine('Analyzing'),
        'Step: Analyzing');
    expect(AppStrings.generationWaitFaceScanMapped(2, 5), '2/5 mapped');
    expect(AppStrings.staffShowingDay('Today'), 'Showing Today');
    expect(AppStrings.staffPaymentCount(1), '1 payment');
    expect(AppStrings.staffPaymentCount(3), '3 payments');
    expect(AppStrings.staffElapsedLine('2h 30m'), '2h 30m elapsed');
    expect(AppStrings.staffRegisterSince('09:00'), 'Since 09:00');
    expect(AppStrings.staffRegisterExpectedLine('₹500'), 'Expected: ₹500');
    expect(AppStrings.staffRegisterReceiptsLine(4), 'Receipts: 4');
    expect(AppStrings.staffRegisterPrintsLine(2), 'Prints: 2');
  });
}
