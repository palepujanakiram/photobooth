import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_payments_session_images.dart';

void main() {
  test('fromPaymentPayload reads sessionImages list', () {
    final urls = StaffPaymentsSessionImages.fromPaymentPayload(
      {
        'sessionImages': [
          'https://cdn/strip.jpg',
          'https://cdn/ai.jpg',
          'https://cdn/strip.jpg',
        ],
      },
      sessionId: 'sess-1',
    );
    expect(urls, hasLength(2));
    expect(urls.first, contains('strip.jpg'));
  });

  test('fromSessionMap prefers strip then surprise then generated', () {
    final urls = StaffPaymentsSessionImages.fromSessionMap(
      {
        'stripCompositeUrl': 'https://cdn/strip.jpg',
        'surpriseImageUrl': 'https://cdn/surprise.jpg',
        'generatedImages': ['https://cdn/gen.jpg'],
        'latestImageUrl': 'https://cdn/latest.jpg',
      },
      sessionId: 'sess-1',
    );
    expect(urls, [
      'https://cdn/strip.jpg',
      'https://cdn/surprise.jpg',
      'https://cdn/gen.jpg',
      'https://cdn/latest.jpg',
    ]);
  });

  test('fromPaymentPayload reads embedded session map', () {
    final urls = StaffPaymentsSessionImages.fromPaymentPayload(
      {
        'session': {
          'stripCompositeUrl': 'https://cdn/strip.jpg',
          'surpriseImageUrl': 'https://cdn/surprise.jpg',
        },
      },
      sessionId: 'sess-1',
    );
    expect(urls, [
      'https://cdn/strip.jpg',
      'https://cdn/surprise.jpg',
    ]);
  });

  test('stripCompositeUrlFromPayment reads top-level and nested session', () {
    expect(
      StaffPaymentsSessionImages.stripCompositeUrlFromPayment(
        {'stripCompositeUrl': 'https://cdn/strip.jpg'},
        sessionId: 'sess-1',
      ),
      contains('strip.jpg'),
    );
    expect(
      StaffPaymentsSessionImages.stripCompositeUrlFromPayment(
        {
          'session': {'stripCompositeUrl': 'https://cdn/nested-strip.jpg'},
        },
        sessionId: 'sess-1',
      ),
      contains('nested-strip.jpg'),
    );
    expect(
      StaffPaymentsSessionImages.stripCompositeUrlFromPayment(
        {
          'sessionImages': ['https://cdn/ai.jpg'],
        },
        sessionId: 'sess-1',
      ),
      isNull,
    );
  });

  test('label and preview helpers', () {
    expect(StaffPaymentsSessionImages.labelForIndex(0, 1), 'Photo');
    expect(StaffPaymentsSessionImages.labelForIndex(1, 3), 'Photo 2');
    expect(
      StaffPaymentsSessionImages.previewUrl('https://cdn/x.jpg'),
      contains('cdn/x.jpg'),
    );
  });
}
