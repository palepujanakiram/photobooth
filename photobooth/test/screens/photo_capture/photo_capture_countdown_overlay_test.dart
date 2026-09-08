import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_countdown_overlay.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  testWidgets('places the timer at the top of the preview', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureCountdownOverlay(countdownValue: 8),
        ),
      ),
    );

    expect(find.text('8'), findsOneWidget);
    final overlay = find.byType(CaptureCountdownOverlay);
    expect(
      tester
          .widget<Align>(
            find.descendant(of: overlay, matching: find.byType(Align)),
          )
          .alignment,
      Alignment.topCenter,
    );
    final scrim = tester.widget<ColoredBox>(
      find.descendant(of: overlay, matching: find.byType(ColoredBox)),
    );
    expect(scrim.color.a, closeTo(kCaptureCountdownScrimAlpha, 0.001));
    final disc = tester.widget<Container>(
      find.descendant(of: overlay, matching: find.byType(Container)),
    );
    final decoration = disc.decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(kCaptureCountdownDiscAlpha, 0.001));
    expect(find.text(AppStrings.captureCountdownIntro), findsNothing);
  });

  testWidgets('shows the intro headline above the numeral', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureCountdownOverlay(
            countdownValue: 5,
            headline: AppStrings.captureCountdownIntro,
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.captureCountdownIntro), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });
}
