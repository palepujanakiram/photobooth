import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_view_widgets.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/views/widgets/app_colors.dart';

void main() {
  group('beholdHeroMessage', () {
    test('ready copy when images are available', () {
      expect(
        beholdHeroMessage(
          isGeneratingOrLoading: false,
          isLoadingMore: false,
          hasImages: true,
        ),
        AppStrings.beholdReadyTitle,
      );
    });

    test('wait copy while first generation runs', () {
      expect(
        beholdHeroMessage(
          isGeneratingOrLoading: true,
          isLoadingMore: false,
          hasImages: false,
        ),
        'Please wait while we create your masterpiece',
      );
    });
  });

  group('isBeholdSingleResultReady', () {
    test('false before any images exist', () {
      expect(isBeholdSingleResultReady(PhotoGenerateViewModel()), isFalse);
    });
  });

  group('fitBeholdHeroAspectInBox', () {
    test('height-limited portrait aspect in wide box', () {
      final size = fitBeholdHeroAspectInBox(
        maxWidth: 800,
        maxHeight: 600,
        aspect: 0.75,
      );
      expect(size.height, 600);
      expect(size.width, 450);
    });

    test('width-limited portrait aspect in tall narrow box', () {
      final size = fitBeholdHeroAspectInBox(
        maxWidth: 400,
        maxHeight: 900,
        aspect: 0.75,
      );
      expect(size.width, 400);
      expect(size.height, closeTo(533.33, 0.01));
    });
  });

  group('buildBeholdReadyScreenLayout', () {
    testWidgets('renders hero, bottom continue, and orientation without scroll', (
      tester,
    ) async {
      const heroKey = Key('behold-ready-hero-test');
      final vm = PhotoGenerateViewModel();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final appColors = AppColors.of(context);
                  return SizedBox(
                    width: 1280,
                    height: 560,
                    child: buildBeholdReadyScreenLayout(
                      context: context,
                      constraints: const BoxConstraints(
                        maxWidth: 1280,
                        maxHeight: 560,
                      ),
                      input: PhotoGenerateMainContentInput(
                        contentKey: GlobalKey(),
                        viewModel: vm,
                        appColors: appColors,
                        isLandscape: true,
                        buildPhotosDisplay: (
                          _,
                          __,
                          ___,
                          ____,
                          _____,
                          ______,
                          _______,
                        ) =>
                            const SizedBox.shrink(),
                        buildPhotosActionFooter: (_, __, ___) =>
                            const SizedBox.shrink(),
                        beholdReadyActions: BeholdReadyActionInput(
                          paymentsEnabled: true,
                          isMounted: true,
                          onAddStyleSelected: (_) {},
                        ),
                        buildBeholdReadyHero: (
                          _,
                          __, {
                          required width,
                          required height,
                        }) =>
                            SizedBox(
                              key: heroKey,
                              width: width,
                              height: height,
                              child: const ColoredBox(color: Colors.red),
                            ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(heroKey), findsOneWidget);
      expect(find.text(AppStrings.beholdContinueLabel), findsOneWidget);
      expect(find.text('Print orientation'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);

      final heroBox = tester.getSize(find.byKey(heroKey));
      expect(heroBox.height, greaterThan(280));

      final continueY = tester.getTopLeft(find.text(AppStrings.beholdContinueLabel)).dy;
      final heroBottom = tester.getBottomLeft(find.byKey(heroKey)).dy;
      expect(continueY, greaterThan(heroBottom));
    });
  });
}
