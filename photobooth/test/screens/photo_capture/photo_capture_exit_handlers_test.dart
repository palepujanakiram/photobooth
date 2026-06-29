import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_exit_handlers.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('releaseCaptureScreenHardware', () {
    test('disposes UVC before CameraX', () async {
      final steps = <String>[];
      await releaseCaptureScreenHardware(
        disposeUvc: () async {
          steps.add('uvc');
        },
        viewModel: CaptureViewModel(),
      );
      expect(steps, ['uvc']);
    });
  });

  group('exitCaptureScreenToTerms', () {
    testWidgets('releases hardware then navigates to Terms', (tester) async {
      final steps = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            AppConstants.kRouteTerms: (_) {
              steps.add('terms');
              return const Scaffold(body: Text('terms'));
            },
          },
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    await exitCaptureScreenToTerms(
                      context: context,
                      isMounted: () => true,
                      releaseCaptureHardware: () async {
                        steps.add('release');
                      },
                      sessionEndContext: 'test',
                      endSession: (context) async {
                        steps.add('session');
                      },
                    );
                  },
                  child: const Text('exit'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('exit'));
      await tester.pumpAndSettle();

      expect(steps, ['release', 'session', 'terms']);
    });
  });
}
