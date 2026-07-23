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
    expect(AppStrings.generationWaitEtaRemaining('45s'), '~45s remaining');
    expect(AppStrings.generationWaitEtaAboutTotal('2m'), 'About 2m total');
    expect(AppStrings.generationWaitEtaTodayAvg('90s'),
        'Today at this booth: ~90s avg');
    expect(AppStrings.generationWaitEtaRecentAvg('80s'),
        'Recent portraits here: ~80s');
    expect(AppStrings.qrShareResettingIn(27), 'Starting fresh in 27s');
    expect(AppStrings.staffShowingDay('Today'), 'Showing Today');
    expect(AppStrings.staffPaymentCount(1), '1 payment');
    expect(AppStrings.staffPaymentCount(3), '3 payments');
    expect(AppStrings.staffElapsedLine('2h 30m'), '2h 30m elapsed');
    expect(AppStrings.staffRegisterSince('09:00'), 'Since 09:00');
    expect(AppStrings.staffRegisterExpectedLine('₹500'), 'Expected: ₹500');
    expect(AppStrings.staffRegisterReceiptsLine(4), 'Receipts: 4');
    expect(AppStrings.staffRegisterPrintsLine(2), 'Prints: 2');
    expect(AppStrings.resultPrintCopiesEach(1), '1 copy each');
    expect(AppStrings.resultPrintCopiesEach(3), '3 copies each');
    expect(AppStrings.resultPrintSheetsLine(1), '1 print total');
    expect(AppStrings.resultPrintSheetsLine(4), '4 prints total');
  });
}
