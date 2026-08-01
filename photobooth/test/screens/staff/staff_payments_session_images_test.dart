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

  test('composePrimaryImageUrlFromSession reads generatedImages s6x4 entry', () {
    expect(
      StaffPaymentsSessionImages.composePrimaryImageUrlFromSession(
        {
          'generatedImages': [
            {
              'imageUrl': 'https://cdn/single6x4.jpg',
              'printSize': 's6x4',
            },
          ],
        },
        sessionId: 's1',
      ),
      contains('single6x4.jpg'),
    );
    expect(
      StaffPaymentsSessionImages.composePrimaryImageUrlFromSession(
        {'generatedImages': 'not-a-list'},
        sessionId: 's1',
      ),
      isNull,
    );
  });

  test('printSizeForImageUrl reads generatedImages and session print block', () {
    expect(
      StaffPaymentsSessionImages.printSizeForImageUrl(
        {
          'generatedImages': [
            {
              'imageUrl': 'https://cdn/single.jpg',
              'printSize': 's6x4',
            },
          ],
        },
        imageUrl: 'https://cdn/single.jpg?sessionId=s1',
        sessionId: 's1',
      ),
      's6x4',
    );
    expect(
      StaffPaymentsSessionImages.printSizeForImageUrl(
        {
          'print': {'size': 's6x2_2'},
          'generatedImages': [
            {'imageUrl': 'https://cdn/strip.jpg'},
          ],
        },
        imageUrl: 'https://cdn/strip.jpg',
        sessionId: 's1',
      ),
      's6x2_2',
    );
    expect(
      StaffPaymentsSessionImages.printSizeForImageUrl(
        {
          'print': {'size': 's6x2_2'},
        },
        imageUrl: 'https://cdn/strip.jpg',
        sessionId: 's1',
      ),
      's6x2_2',
    );
    expect(
      StaffPaymentsSessionImages.printSizeForImageUrl(
        {
          'generatedImages': [
            {'imageUrl': 'https://cdn/other.jpg'},
          ],
          'printSize': 's5x7',
        },
        imageUrl: 'https://cdn/unrelated.jpg',
        sessionId: 's1',
      ),
      's5x7',
    );
  });

  test('classicComposeShotCountFromSession reads capturedImages length', () {
    expect(
      StaffPaymentsSessionImages.classicComposeShotCountFromSession(
        {'capturedImages': ['a']},
      ),
      1,
    );
    expect(
      StaffPaymentsSessionImages.classicComposeShotCountFromSession(
        {'capturedImages': List.filled(4, 'a')},
      ),
      4,
    );
    expect(
      StaffPaymentsSessionImages.classicComposeShotCountFromSession(
        {'shotCount': 1},
      ),
      1,
    );
    expect(
      StaffPaymentsSessionImages.classicComposeShotCountFromSession(
        {'shot_count': 4},
      ),
      4,
    );
  });

  test('composePrimaryImageUrlFromSession prefers imageUrl field', () {
    expect(
      StaffPaymentsSessionImages.composePrimaryImageUrlFromSession(
        {
          'imageUrl': 'https://cdn/single6x4.jpg',
          'stripCompositeUrl': 'https://cdn/strip.jpg',
        },
        sessionId: 's1',
      ),
      contains('single6x4.jpg'),
    );
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
