import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/fotoflashback_payment_helpers.dart';
import 'package:photobooth/utils/route_args.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
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
}
