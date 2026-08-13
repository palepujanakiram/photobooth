import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view_aspect.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('applyDefaultPreviewRotationForUvc is no-op when rotation is 0', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    viewModel.applyDefaultPreviewRotationForUvc();
    expect(viewModel.previewRotationDegrees, 0);
  });

  test('applyDefaultPreviewRotationForUvc keeps staff 90° for portrait TV',
      () async {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.setPreviewRotation(90);
    expect(viewModel.previewRotationDegrees, 90);
    expect(viewModel.uvcPreviewEffectiveQuarterTurns, 1);
    expect(
      viewModel.bakeQuarterTurnsMatchingLiveFeed(fromSidecar: true),
      4,
      reason: 'FOTO bake locked to 4 (≡0; EXIF-only)',
    );
    expect(
      viewModel.bakeQuarterTurnsMatchingLiveFeed(fromSidecar: false),
      4,
      reason: 'FOTO bake locked to 4 (≡0; EXIF-only)',
    );

    // UVC rebind must not wipe staff portrait-TV rotation.
    viewModel.applyDefaultPreviewRotationForUvc();
    expect(viewModel.previewRotationDegrees, 90);
    expect(
      viewModel.bakeQuarterTurnsMatchingLiveFeed(fromSidecar: true),
      4,
    );
  });

  test('HDMI+sidecar bake stays locked to 4 when live preview is 0', () async {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    await viewModel.loadPreviewRotation();
    expect(viewModel.previewRotationDegrees, 0);
    expect(viewModel.sidecarHdmiStillExtraQuarterTurns, 0);
    expect(
      viewModel.bakeQuarterTurnsMatchingLiveFeed(fromSidecar: true),
      4,
      reason: 'FOTO bake locked to 4 (≡0; EXIF-only)',
    );
    expect(
      viewModel.bakeQuarterTurnsMatchingLiveFeed(fromSidecar: false),
      4,
      reason: 'FOTO bake locked to 4 (≡0; EXIF-only)',
    );
  });

  test('lockCaptureCardAspectRatio clamps external preview aspect', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    viewModel.lockCaptureCardAspectRatio(1.78);
    expect(viewModel.lockedCaptureCardAspectRatio, closeTo(1.78, 0.001));

    viewModel.lockCaptureCardAspectRatio(0.1);
    expect(viewModel.lockedCaptureCardAspectRatio, 0.35);
  });

  testWidgets('captureCardAspectRatio uses viewport slot on phone portrait', (
    WidgetTester tester,
  ) async {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              const constraints = BoxConstraints(maxWidth: 360, maxHeight: 480);
              final aspect = captureCardAspectRatio(
                context,
                viewModel,
                false,
                AppConstants.themeCardSlotAspectRatio(context),
                constraints,
              );
              expect(aspect, closeTo(360 / 480, 0.01));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

  testWidgets(
    'phone portrait live preview uses viewport even when sensor is landscape',
    (WidgetTester tester) async {
      final viewModel = CaptureViewModel();
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Builder(
              builder: (context) {
                const constraints =
                    BoxConstraints(maxWidth: 360, maxHeight: 520);
                // Without a live controller, liveAspect is null → viewport path.
                final aspect = captureCardAspectRatioForLivePreview(
                  context: context,
                  viewModel: viewModel,
                  fallbackAspect: 0.75,
                  layoutConstraints: constraints,
                );
                expect(aspect, closeTo(360 / 520, 0.01));
                expect(aspect, lessThan(1.0));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    },
  );

  testWidgets(
    'phone portrait ignores landscape UVC buffer for live card aspect',
    (WidgetTester tester) async {
      final viewModel = CaptureViewModel();
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Builder(
              builder: (context) {
                const constraints =
                    BoxConstraints(maxWidth: 360, maxHeight: 520);
                final aspect = captureCardAspectRatioForLivePreview(
                  context: context,
                  viewModel: viewModel,
                  fallbackAspect: 0.75,
                  layoutConstraints: constraints,
                  uvcPreviewDisplaySize: const Size(1920, 1080),
                );
                expect(aspect, closeTo(360 / 520, 0.01));
                expect(aspect, lessThan(1.0));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    },
  );

  test('captureCardDecodedImageAspect returns landscape for wide photos', () {
    expect(
      captureCardDecodedImageAspect(const Size(1920, 1080)),
      closeTo(1920 / 1080, 0.001),
    );
    expect(captureCardDecodedImageAspect(null), isNull);
  });

  test('captureCardAspectRatioFromPersonCount landscape for groups', () {
    expect(
      captureCardAspectRatioFromPersonCount(4),
      AppConstants.kBeholdSingleResultDefaultAspectRatio,
    );
    expect(captureCardAspectRatioFromPersonCount(2), isNull);
    expect(captureCardAspectRatioFromPersonCount(null), isNull);
  });

  testWidgets(
    'preferThemeSlotAspect keeps landscape kiosk on portrait theme slot',
    (WidgetTester tester) async {
      final viewModel = CaptureViewModel();
      addTearDown(viewModel.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 800)),
            child: Builder(
              builder: (context) {
                const constraints =
                    BoxConstraints(maxWidth: 600, maxHeight: 700);
                final fallback =
                    AppConstants.themeCardSlotAspectRatio(context);
                expect(fallback, lessThan(1.0));
                final live = captureCardAspectRatioForLivePreview(
                  context: context,
                  viewModel: viewModel,
                  fallbackAspect: fallback,
                  layoutConstraints: constraints,
                  uvcPreviewDisplaySize: const Size(1920, 1080),
                  preferThemeSlotAspect: true,
                );
                expect(live, closeTo(fallback, 0.001));
                final captured = captureCardAspectRatioForCaptured(
                  context: context,
                  viewModel: viewModel,
                  fallbackAspect: fallback,
                  layoutConstraints: constraints,
                  preferThemeSlotAspect: true,
                );
                expect(captured, closeTo(fallback, 0.001));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    },
  );

  testWidgets(
    'captured sidecar still uses decoded landscape over live lock',
    (WidgetTester tester) async {
      final viewModel = CaptureViewModel();
      addTearDown(viewModel.dispose);
      viewModel.lockCaptureCardAspectRatio(0.67);
      viewModel.setCapturedImagePixelSizeForTest(const Size(1920, 1280));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1920, 1080)),
            child: Builder(
              builder: (context) {
                const constraints =
                    BoxConstraints(maxWidth: 900, maxHeight: 800);
                final aspect = captureCardAspectRatioForCaptured(
                  context: context,
                  viewModel: viewModel,
                  fallbackAspect: 0.67,
                  layoutConstraints: constraints,
                  preferThemeSlotAspect: false,
                );
                expect(aspect, closeTo(1920 / 1280, 0.001));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    },
  );

  testWidgets('captureCardAspectRatioForCaptured uses decoded image aspect', (
    WidgetTester tester,
  ) async {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);
    viewModel.lockCaptureCardAspectRatio(0.75);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              const constraints = BoxConstraints(maxWidth: 360, maxHeight: 480);
              final withLocked = captureCardAspectRatioForCaptured(
                context: context,
                viewModel: viewModel,
                fallbackAspect: 0.75,
                layoutConstraints: constraints,
              );
              expect(withLocked, closeTo(0.75, 0.001));
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });
}
