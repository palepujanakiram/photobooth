import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_payments_preview_helpers.dart';

void main() {
  test('staffPaymentShowImagePreview ignores empty url', () {
    staffPaymentShowImagePreview(
      _FakeBuildContext(),
      imageUrl: '  ',
    );
  });

  testWidgets('staffPaymentShowImagePreview dedupes imageUrls list',
      (tester) async {
    const pngDataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                staffPaymentShowImagePreview(
                  context,
                  imageUrl: pngDataUrl,
                  imageUrls: ['  ', pngDataUrl, 'https://example.com/other.jpg'],
                  title: 'Payment',
                );
              },
              child: const Text('preview'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('preview'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffPaymentImagePreviewScreen), findsOneWidget);
  });

  testWidgets('staffPaymentShowImagePreview opens preview screen', (tester) async {
    const pngDataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                staffPaymentShowImagePreview(
                  context,
                  imageUrl: pngDataUrl,
                  title: 'Payment',
                  subtitle: 'Guest photo',
                );
              },
              child: const Text('preview'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('preview'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffPaymentImagePreviewScreen), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Guest photo'), findsOneWidget);
  });

  testWidgets('StaffPaymentImagePreviewScreen close button pops route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StaffPaymentImagePreviewScreen(
                      imageUrls: ['not-valid-image'],
                      title: 'Payment',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffPaymentImagePreviewScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(StaffPaymentImagePreviewScreen), findsNothing);
  });

  test('staffPaymentLoadImageBytes decodes data URLs', () async {
    final bytes = await staffPaymentLoadImageBytes(
      imageUrl: 'data:image/png;base64,YWJj',
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), 'abc');
  });

  test('staffPaymentLoadImageBytes returns null for empty url', () async {
    expect(
      await staffPaymentLoadImageBytes(imageUrl: '  '),
      isNull,
    );
  });

  test('staffPaymentLoadImageBytes decodes long base64 payloads', () async {
    final payload = base64Encode(List<int>.filled(120, 65));
    final bytes = await staffPaymentLoadImageBytes(imageUrl: payload);
    expect(bytes, isNotNull);
    expect(bytes!.length, 120);
  });

  test('staffPaymentLoadImageBytes returns null for invalid data url', () async {
    expect(
      await staffPaymentLoadImageBytes(imageUrl: 'data:image/png;base64,!!!'),
      isNull,
    );
  });

  test('staffPaymentLoadImageBytes returns null for protected fetch failures', () async {
    expect(
      await staffPaymentLoadImageBytes(
        imageUrl: 'https://fotozenai.fly.dev/api/img/test.jpg',
      ),
      isNull,
    );
  });

  testWidgets('StaffPaymentImagePreviewScreen shows failure icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StaffPaymentImagePreviewScreen(imageUrls: ['not-valid-image']),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.exclamationmark_triangle), findsOneWidget);
  });

  testWidgets('multi-photo preview shows nav controls and advances pages',
      (tester) async {
    const pngDataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await tester.pumpWidget(
      const MaterialApp(
        home: StaffPaymentImagePreviewScreen(
          imageUrls: [pngDataUrl, pngDataUrl],
          title: 'Payment',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Next photo'), findsOneWidget);
    expect(find.byTooltip('Previous photo'), findsOneWidget);
    expect(find.text('Photo 1 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo 2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo 1 / 2'), findsOneWidget);
  });

  testWidgets('single-photo preview hides multi-photo nav controls',
      (tester) async {
    const pngDataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await tester.pumpWidget(
      const MaterialApp(
        home: StaffPaymentImagePreviewScreen(
          imageUrls: [pngDataUrl],
          title: 'Payment',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Next photo'), findsNothing);
    expect(find.byTooltip('Previous photo'), findsNothing);
    expect(find.textContaining('Photo 1 /'), findsNothing);
  });
}

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
