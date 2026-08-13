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
    expect(AppStrings.staffThemeSwitchToLight, isNotEmpty);
    expect(AppStrings.staffThemeSwitchToDark, isNotEmpty);
    expect(AppStrings.staffThemeLightLabel, isNotEmpty);
    expect(AppStrings.staffThemeDarkLabel, isNotEmpty);
    expect(AppStrings.staffBackToStartTooltip, isNotEmpty);
    expect(AppStrings.receiptPrintSuccess, isNotEmpty);
    expect(AppStrings.receiptPrintNotConfigured, isNotEmpty);
    expect(AppStrings.receiptPrintFailedGeneric, isNotEmpty);
    expect(AppStrings.receiptPrintEmptyPayload, isNotEmpty);
    expect(AppStrings.receiptPrintUnsupportedOnWeb, isNotEmpty);
    expect(AppStrings.printReceiptButton, isNotEmpty);
    expect(AppStrings.printingReceiptButton, isNotEmpty);
    expect(AppStrings.staffNoKioskForRegister, isNotEmpty);
    expect(AppStrings.themeSelectionContinue, isNotEmpty);
    expect(AppStrings.themeSelectionContinuing, isNotEmpty);
    expect(AppStrings.sidecarLivePreviewConnecting, isNotEmpty);
    expect(AppStrings.sidecarLivePreviewUnavailable, isNotEmpty);
    expect(AppStrings.kioskDeviceDslrSidecar, isNotEmpty);
    expect(AppStrings.kioskDeviceTransportLan, isNotEmpty);
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
    expect(
      AppStrings.flashbackReviewHoldStatus(isLastShot: false, secondsLeft: 8),
      'Rearrange for the next pose…  8',
    );
    expect(
      AppStrings.flashbackReviewHoldStatus(
        isLastShot: false,
        secondsLeft: 8,
        nextShot: 2,
        total: 4,
      ),
      'Rearrange for Shot 2 of 4  8',
    );
    expect(
      AppStrings.flashbackReviewHoldStatus(isLastShot: true, secondsLeft: 3),
      'Looking good! Continuing soon…  3',
    );
    expect(
      AppStrings.flashbackReviewHoldStatus(isLastShot: false, secondsLeft: 0),
      AppStrings.flashbackGettingReadyNextShot,
    );
    expect(
      AppStrings.flashbackGetReadyForShot(2, 4),
      'Get ready — Shot 2 of 4',
    );
    expect(
      AppStrings.flashbackPoseProgress(1, 4),
      'Pose now — Shot 1 of 4',
    );
    expect(
      AppStrings.flashbackCaptureSubtitle,
      contains('10s'),
    );
    expect(
      AppStrings.flashbackCaptureSubtitle,
      contains('8s'),
    );
    expect(AppStrings.captureMaskStallRetry, contains('Tap Capture'));
    expect(AppStrings.printSelectionTotal(250), 'Total ₹250');
    expect(AppStrings.printSelectionContinue(0), 'Select a photo');
    expect(AppStrings.printSelectionContinue(2), 'Continue (2)');
    expect(AppStrings.flashbackSinglePrintTitle(true), 'Classic 4×6');
    expect(AppStrings.flashbackSinglePrintTitle(false), 'Classic 6×4');
  });
}
