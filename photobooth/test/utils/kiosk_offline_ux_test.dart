import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/services/local_kiosk_models.dart';
import 'package:photobooth/services/local_session_skeleton.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/kiosk_offline_ux.dart';

void main() {
  test('sessionPayloadIsOffline reads the skeleton flag', () {
    expect(KioskOfflineUx.sessionPayloadIsOffline(null), isFalse);
    expect(KioskOfflineUx.sessionPayloadIsOffline({'id': 's'}), isFalse);
    expect(
      KioskOfflineUx.sessionPayloadIsOffline({kKioskSessionOfflineKey: true}),
      isTrue,
    );
    expect(
      KioskOfflineUx.sessionPayloadIsOffline({kKioskSessionOfflineKey: false}),
      isFalse,
    );
  });

  test('shouldSkipAiGeneration is true offline or on WAN-down errors', () {
    expect(
      KioskOfflineUx.shouldSkipAiGeneration(sessionOffline: true),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldSkipAiGeneration(sessionOffline: false),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldSkipAiGeneration(
        sessionOffline: false,
        error: TimeoutException('t'),
      ),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldSkipAiGeneration(
        sessionOffline: false,
        error: ApiException('nope', 400),
      ),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldSkipAiGeneration(
        sessionOffline: false,
        error: ApiException(AppConstants.kErrorNetwork, 400),
      ),
      isTrue,
    );
  });

  test('cash-only and hide-discount / skip-prepay flags', () {
    expect(
      KioskOfflineUx.shouldUseCashOnlyPayments(sessionOffline: true),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldUseCashOnlyPayments(
        sessionOffline: false,
        error: ApiException('x', 503),
      ),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldHideCloudDiscounts(sessionOffline: true),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldHideCloudDiscounts(sessionOffline: false),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldSkipUpiPrePayment(sessionOffline: true),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldSkipUpiPrePayment(sessionOffline: false),
      isFalse,
    );
  });

  test('shouldUseLocalStripLook ignores online timeouts and 4xx', () {
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(sessionOffline: true),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: TimeoutException('t'),
      ),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: ApiException('compose down'),
      ),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: ApiException('x', 400),
      ),
      isFalse,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: ApiException('x', 503),
      ),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: ApiException(AppConstants.kErrorNetwork),
      ),
      isTrue,
    );
    expect(
      KioskOfflineUx.shouldUseLocalStripLook(
        sessionOffline: false,
        error: StateError('boom'),
      ),
      isFalse,
    );
  });

  test('firstNonEmptyDataUrl and localLookComposeResult', () {
    expect(firstNonEmptyDataUrl(const []), '');
    expect(firstNonEmptyDataUrl(const ['  ', 'a', 'b']), 'a');
    final result = localLookComposeResult(
      imageUrl: 'data:image/jpeg;base64,xx',
      filterId: 'noir',
      printSize: AppConstants.kPrintSizePortrait4x6,
    );
    expect(result, isA<StripComposeResult>());
    expect(result.imageUrl, 'data:image/jpeg;base64,xx');
    expect(result.filter, 'noir');
    expect(result.copiesOnSheet, 1);
    expect(result.printImageUrl, 'data:image/jpeg;base64,xx');
  });

  test('localBoothCloseTotals sums cash only', () {
    const counts = LocalDayCounts(
      sessions: 4,
      payments: 3,
      printJobs: 2,
      receipts: 1,
    );
    final totals = localBoothCloseTotals(
      counts: counts,
      paymentPayloads: [
        {'paymentMode': 'CASH', 'amount': 200},
        {'paymentMode': 'UPI', 'amount': 300},
        {'paymentMode': 'CASH', 'amount': -5},
        {'paymentMode': 'COMPLIMENTARY', 'amount': 0},
        {'amount': 50},
      ],
    );
    expect(totals.sessions, 4);
    expect(totals.printJobs, 2);
    expect(totals.receipts, 1);
    expect(totals.paymentCount, 3);
    expect(totals.cashCount, 2);
    expect(totals.cashAmount, 200);
  });
}
