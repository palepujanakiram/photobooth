import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/splash/splash_outbox_sync_panel.dart';
import 'package:photobooth/services/local_kiosk_models.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/views/widgets/app_colors.dart';

void main() {
  testWidgets('shows pending count and Sync now', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoPageScaffold(
              child: SplashOutboxSyncPanel(
                appColors: AppColors.of(context),
                counts: const KioskOutboxSyncCounts(pending: 2, failed: 1),
                syncing: false,
                completedThisRun: 0,
                onSyncPressed: () => tapped = true,
              ),
            );
          },
        ),
      ),
    );
    expect(find.text(AppStrings.splashSyncPending(3, 1)), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text(AppStrings.splashSyncNowButton));
    expect(tapped, isTrue);
  });

  testWidgets('disables button while syncing and shows progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return CupertinoPageScaffold(
              child: SplashOutboxSyncPanel(
                appColors: AppColors.of(context),
                counts: const KioskOutboxSyncCounts(pending: 2),
                syncing: true,
                completedThisRun: 5,
                onSyncPressed: () {},
              ),
            );
          },
        ),
      ),
    );
    expect(find.text(AppStrings.splashSyncProgress(5, 2)), findsOneWidget);
    expect(find.text(AppStrings.splashSyncingButton), findsOneWidget);
    final button = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
    expect(button.onPressed, isNull);
  });
}
