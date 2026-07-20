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
        home: StaffPaymentImagePreviewScreen(imageUrl: 'not-valid-image'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.exclamationmark_triangle), findsOneWidget);
  });
}

class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
