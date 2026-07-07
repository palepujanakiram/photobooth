import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/payment_workflow_helpers.dart';

void main() {
  group('collectPaymentBeforeGeneration', () {
    test('true only for before_generation', () {
      expect(
        collectPaymentBeforeGeneration(
          AppConstants.kPaymentCollectionBeforeGeneration,
        ),
        isTrue,
      );
      expect(
        collectPaymentBeforeGeneration(
          AppConstants.kPaymentCollectionAfterGeneration,
        ),
        isFalse,
      );
      expect(collectPaymentBeforeGeneration(null), isFalse);
    });
  });

  group('resolveCheckoutAmount', () {
    test('after_generation charges full cart', () {
      expect(
        resolveCheckoutAmount(
          collectPaymentBeforeGeneration: false,
          imageCount: 1,
          initialPrintPrice: 100,
          additionalPrintPrice: 50,
        ),
        100,
      );
      expect(
        resolveCheckoutAmount(
          collectPaymentBeforeGeneration: false,
          imageCount: 3,
          initialPrintPrice: 100,
          additionalPrintPrice: 50,
        ),
        200,
      );
    });

    test('before_generation skips initial when one print', () {
      expect(
        resolveCheckoutAmount(
          collectPaymentBeforeGeneration: true,
          imageCount: 1,
          initialPrintPrice: 100,
          additionalPrintPrice: 50,
        ),
        0,
      );
    });

    test('before_generation charges only extra prints', () {
      expect(
        resolveCheckoutAmount(
          collectPaymentBeforeGeneration: true,
          imageCount: 3,
          initialPrintPrice: 100,
          additionalPrintPrice: 50,
        ),
        100,
      );
    });
  });

  group('resolvePostFrameRoute', () {
    test('pre-payment when enabled and configured', () {
      expect(
        resolvePostFrameRoute(
          paymentsEnabled: true,
          paymentCollectionTiming:
              AppConstants.kPaymentCollectionBeforeGeneration,
        ),
        AppConstants.kRoutePrePayment,
      );
    });

    test('generate progress by default', () {
      expect(
        resolvePostFrameRoute(
          paymentsEnabled: true,
          paymentCollectionTiming:
              AppConstants.kPaymentCollectionAfterGeneration,
        ),
        AppConstants.kRouteGenerateProgress,
      );
      expect(
        resolvePostFrameRoute(
          paymentsEnabled: false,
          paymentCollectionTiming:
              AppConstants.kPaymentCollectionBeforeGeneration,
        ),
        AppConstants.kRouteGenerateProgress,
      );
    });
  });
}
