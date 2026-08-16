import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/views/widgets/flashback_review_hold_banner.dart';

void main() {
  testWidgets('FlashbackReviewHoldBanner shows countdown for endsAt',
      (tester) async {
    final endsAt = DateTime.now().add(const Duration(seconds: 8));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlashbackReviewHoldBanner(
            endsAt: endsAt,
            isLastShot: false,
            nextShot: 2,
            total: 4,
          ),
        ),
      ),
    );

    final text = (find
            .textContaining('Rearrange for Shot 2 of 4')
            .evaluate()
            .single
            .widget as Text)
        .data!;
    expect(text, contains('Rearrange for Shot 2 of 4'));
    final seconds =
        int.parse(RegExp(r'(\d+)\s*$').firstMatch(text)!.group(1)!);
    expect(seconds, inInclusiveRange(7, 8));
  });

  testWidgets('last-shot banner uses continuing-soon copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlashbackReviewHoldBanner(
            endsAt: DateTime.now().add(const Duration(seconds: 5)),
            isLastShot: true,
          ),
        ),
      ),
    );
    expect(
      find.textContaining(AppStrings.flashbackReviewLastShot),
      findsOneWidget,
    );
  });
}
