import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/fotoflashback_payment_helpers.dart';
import 'package:photobooth/utils/route_args.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flashbackContinueCta reflects payment timing', () {
    expect(
      flashbackContinueCta(
        paymentsEnabled: true,
        paymentCollectionTiming:
            AppConstants.kPaymentCollectionBeforeGeneration,
      ),
      AppStrings.flashbackComposePayCta,
    );
    expect(
      flashbackContinueCta(
        paymentsEnabled: true,
        paymentCollectionTiming:
            AppConstants.kPaymentCollectionAfterGeneration,
      ),
      AppStrings.flashbackComposeCta,
    );
    expect(
      flashbackContinueCta(
        paymentsEnabled: false,
        paymentCollectionTiming:
            AppConstants.kPaymentCollectionBeforeGeneration,
      ),
      AppStrings.flashbackComposeCta,
    );
  });

  test('FlashbackPrePayArgs.tryParse validates four images', () {
    final theme = sampleTheme('t').copyWith((p) => p.tier = 'photo_strip');
    final typed = FlashbackPrePayArgs(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:x'),
      filterId: 'mono',
    );
    expect(FlashbackPrePayArgs.tryParse(typed), same(typed));
    expect(
      FlashbackPrePayArgs.tryParse({
        'theme': theme,
        'filterId': 'clean',
        'imageDataUrls': ['a', 'b', 'c'],
      }),
      isNull,
    );
    final ok = FlashbackPrePayArgs.tryParse({
      'theme': theme,
      'filterId': 'clean',
      'images': ['a', 'b', 'c', 'd'],
    });
    expect(ok!.filterId, 'clean');
    expect(ok.imageDataUrls, hasLength(4));
  });

  testWidgets('navigateToFlashbackResult includes optional surprise image',
      (tester) async {
    final theme = sampleTheme('t').copyWith((p) => p.tier = 'photo_strip');
    final strip = GeneratedImage(
      id: 'strip',
      imageUrl: 'https://example.com/strip.jpg',
      theme: theme,
      printSize: AppConstants.kPrintSizeStripDual2x6,
    );
    final surprise = GeneratedImage(
      id: 'ai',
      imageUrl: 'https://example.com/ai.jpg',
      theme: sampleTheme('ai'),
      printSize: AppConstants.kPrintSizePortrait4x6,
    );
    Object? capturedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFlashbackResult(
                  context: context,
                  image: strip,
                  surpriseImage: surprise,
                );
              },
              child: const Text('go'),
            );
          },
        ),
        routes: {
          AppConstants.kRouteResult: (context) {
            capturedArgs = ModalRoute.of(context)?.settings.arguments;
            return const SizedBox();
          },
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final args = capturedArgs as ResultArgs;
    expect(args.generatedImages, hasLength(2));
    expect(args.generatedImages[1].id, 'ai');
    expect(
      args.generatedImages[0].printSize,
      AppConstants.kPrintSizeStripDual2x6,
    );
  });
}
