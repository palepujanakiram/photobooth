import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_behold_aspect.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';

void main() {
  testWidgets('beholdCardIsPhonePortrait true when portrait and narrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final result = beholdCardIsPhonePortrait(context);
              expect(result, isTrue);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

  test('beholdHeroContentAspectRatio uses decoded aspect when set', () {
    final vm = PhotoGenerateViewModel()..setBeholdHeroAspectRatioForTest(1.5);
    expect(beholdHeroContentAspectRatio(vm), 1.5);
  });

  test('beholdHeroContentAspectRatio defaults to 2:3', () {
    final vm = PhotoGenerateViewModel();
    expect(beholdHeroContentAspectRatio(vm), closeTo(2 / 3, 0.0001));
  });

  test('fitBeholdHeroAspectInBox width-limited branch', () {
    final size = fitBeholdHeroAspectInBox(
      maxWidth: 100,
      maxHeight: 200,
      aspect: 2,
    );
    expect(size.width, 100);
    expect(size.height, 50);
  });

  test('beholdSingleResultHeroImageFit always contains', () {
    expect(
      beholdSingleResultHeroImageFit(PrintOrientation.portrait),
      BoxFit.contain,
    );
    expect(
      beholdSingleResultHeroImageFit(PrintOrientation.landscape),
      BoxFit.contain,
    );
  });

  test('beholdUsesLandscapePrintMat for portrait art on landscape print', () {
    expect(
      beholdUsesLandscapePrintMat(
        printOrientation: PrintOrientation.landscape,
        contentAspect: 2 / 3,
      ),
      isTrue,
    );
    expect(
      beholdUsesLandscapePrintMat(
        printOrientation: PrintOrientation.portrait,
        contentAspect: 2 / 3,
      ),
      isFalse,
    );
    expect(
      beholdUsesLandscapePrintMat(
        printOrientation: PrintOrientation.landscape,
        contentAspect: 3 / 2,
      ),
      isFalse,
    );
  });

  test('beholdLandscapePrintMatPhotoSize keeps portrait art inside sheet', () {
    final photo = beholdLandscapePrintMatPhotoSize(
      cardWidth: 360,
      cardHeight: 240,
      contentAspect: 2 / 3,
    );
    expect(photo.height, lessThanOrEqualTo(240));
    expect(photo.width, lessThan(360));
    expect(photo.width / photo.height, closeTo(2 / 3, 0.01));
  });

  testWidgets('beholdSingleResultCardAspectRatio follows print orientation', (
    tester,
  ) async {
    final vm = PhotoGenerateViewModel();
    vm.setPrintOrientation(PrintOrientation.landscape);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final aspect = beholdSingleResultCardAspectRatio(
              context,
              vm,
              maxWidth: 360,
              maxHeight: 420,
            );
            expect(aspect, AppConstants.kBeholdSingleResultDefaultAspectRatio);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    vm.setPrintOrientation(PrintOrientation.portrait);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final aspect = beholdSingleResultCardAspectRatio(
              context,
              vm,
              maxWidth: 360,
              maxHeight: 420,
            );
            expect(aspect, AppConstants.kThemeSelectedCardAspectRatio);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
