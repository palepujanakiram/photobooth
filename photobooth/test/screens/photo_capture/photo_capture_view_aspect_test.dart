import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_view_aspect.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('applyDefaultPreviewRotationForUvc clears manual rotation', () {
    final viewModel = CaptureViewModel();
    addTearDown(viewModel.dispose);

    viewModel.applyDefaultPreviewRotationForUvc();
    expect(viewModel.previewRotationDegrees, 0);
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
}
