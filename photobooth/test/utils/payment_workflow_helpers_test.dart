import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/payment_workflow_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KioskManager.resetPaymentOverrideCacheForTests();
  });
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

  group('resolvePaymentsEnabled', () {
    test('defaults to true when override unset', () async {
      expect(await resolvePaymentsEnabled(), isTrue);
    });

    test('respects kiosk override false', () async {
      await KioskManager().setPaymentEnabledOverride(false);
      expect(await resolvePaymentsEnabled(), isFalse);
    });
  });

  group('navigateToGenerationOrPrePayment', () {
    testWidgets('pushes pre-payment when configured', (tester) async {
      await KioskManager().setPaymentEnabledOverride(true);
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      navigateToGenerationOrPrePayment(
                        context: context,
                        photo: _testPhoto(),
                        theme: _testTheme(),
                        replace: false,
                        paymentCollectionTiming:
                            AppConstants.kPaymentCollectionBeforeGeneration,
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
            AppConstants.kRoutePrePayment: (_) =>
                const Scaffold(body: Text('pre-pay')),
            AppConstants.kRouteGenerateProgress: (_) =>
                const Scaffold(body: Text('generate')),
          },
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('pre-pay'), findsOneWidget);
    });

    testWidgets('pushReplacement navigates to generate progress', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (_) => Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      navigateToGenerationOrPrePayment(
                        context: context,
                        photo: _testPhoto(),
                        theme: _testTheme(),
                        replace: true,
                        paymentCollectionTiming:
                            AppConstants.kPaymentCollectionAfterGeneration,
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
            AppConstants.kRouteGenerateProgress: (_) =>
                const Scaffold(body: Text('generate')),
          },
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('generate'), findsOneWidget);
    });
  });
}

PhotoModel _testPhoto() {
  return PhotoModel.fromJson({
    'id': 'p1',
    'imagePath': '/tmp/p.jpg',
    'capturedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
  });
}

ThemeModel _testTheme() {
  return ThemeModel.fromJson({
    'id': 't1',
    'categoryId': 'c1',
    'name': 'Theme',
    'description': 'd',
    'promptText': 'p',
    'sampleImageUrl': 'https://cdn/sample.jpg',
  });
}
