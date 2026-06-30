import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_exit_handlers.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('releaseCaptureScreenHardware', () {
    test('disposes CameraX session', () async {
      final viewModel = CaptureViewModel();
      addTearDown(viewModel.dispose);

      await releaseCaptureScreenHardware(viewModel: viewModel);
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

    testWidgets('skips session end when endCustomerSession is false', (
      tester,
    ) async {
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
                      sessionEndContext: 'capture_back',
                      endCustomerSession: false,
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

      expect(steps, ['release', 'terms']);
    });

    testWidgets('continues to Terms when hardware release fails', (
      tester,
    ) async {
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
                        throw StateError('camera dispose failed');
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
