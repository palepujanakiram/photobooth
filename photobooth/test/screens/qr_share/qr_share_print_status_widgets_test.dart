import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/qr_share/qr_share_print_status_widgets.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/print_progress_helpers.dart';

void main() {
  testWidgets('QrSharePrintStatusCard hidden for idle and skipped', (tester) async {
    for (final phase in [
      PrintProgressPhase.idle,
      PrintProgressPhase.skipped,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrSharePrintStatusCard(
              progress: PrintProgressSnapshot(phase: phase),
            ),
          ),
        ),
      );
      expect(find.byType(QrSharePrintStatusCard), findsOneWidget);
      expect(find.text(AppStrings.printProgressTitleActive), findsNothing);
    }
  });

  testWidgets('QrSharePrintStatusCard shows active progress', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QrSharePrintStatusCard(
            progress: PrintProgressSnapshot(
              phase: PrintProgressPhase.sending,
              percent: 42,
              currentPage: 1,
              totalPages: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.printProgressTitleActive), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byIcon(Icons.print_outlined), findsOneWidget);
  });

  testWidgets('QrSharePrintStatusCard shows complete state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QrSharePrintStatusCard(
            progress: PrintProgressSnapshot(
              phase: PrintProgressPhase.complete,
              percent: 100,
              currentPage: 2,
              totalPages: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.printProgressTitleComplete), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('QrSharePrintStatusCard shows failed state with custom error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QrSharePrintStatusCard(
            progress: PrintProgressSnapshot(
              phase: PrintProgressPhase.failed,
              percent: 10,
              errorMessage: 'Paper jam',
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.printProgressTitleFailed), findsOneWidget);
    expect(find.text('Paper jam'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
