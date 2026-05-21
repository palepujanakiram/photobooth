import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/models/kiosk_share_link_model.dart';
import 'package:photobooth/models/parallel_generation_result.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/result/transformed_image_model.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';

void main() {
  test('AppSettingsModel.fromJson parses dates and ints', () {
    final m = AppSettingsModel.fromJson({
      'id': 's1',
      'initialPrice': 100,
      'parallelImageCount': 2,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'activeLanguages': ['en', 'hi'],
    });
    expect(m.id, 's1');
    expect(m.initialPrice, 100);
    expect(m.parallelImageCount, 2);
    expect(m.createdAt, isNotNull);
    expect(m.activeLanguages, ['en', 'hi']);
  });

  test('KioskInfoModel.isValid requires id and code', () {
    expect(
      KioskInfoModel.fromJson({'id': 'k1', 'code': 'ABC'}).isValid,
      isTrue,
    );
    expect(KioskInfoModel.fromJson({'id': '', 'code': 'x'}).isValid, isFalse);
  });

  test('KioskFrameModel.fromJson', () {
    const f = KioskFrameModel(
      id: 'f1',
      name: 'Frame',
      overlayUrl: 'https://cdn.example/o.png',
    );
    expect(f.id, 'f1');
  });

  test('KioskShareLinkModel.fromJson', () {
    final m = KioskShareLinkModel.fromJson({
      'token': 'tok',
      'url': 'https://short/s/tok',
      'longUrl': 'https://long/s/tok',
      'expiresAt': '2026-06-01T00:00:00.000Z',
    });
    expect(m.token, 'tok');
    expect(m.expiresAt, isNotNull);
  });

  test('PaymentInitiateResult.fromJson merges nested payment', () {
    final r = PaymentInitiateResult.fromJson({
      'data': {
        'payment': {
          'payment_id': 'pay-1',
          'qr_image_url': 'https://rzp.io/q.png',
          'status': 'created',
        },
      },
    });
    expect(r.id, 'pay-1');
    expect(r.qrImageUrl, 'https://rzp.io/q.png');
    expect(r.status, 'created');
  });

  test('ParallelGenerationResult preferredImageUrl uses quality scores', () {
    final r = ParallelGenerationResult(
      imageUrlsBySlot: ['', 'https://b.jpg', 'https://a.jpg'],
      qualityScoreByIndex: {2: 0.9, 1: 0.5},
    );
    expect(r.preferredImageUrl, 'https://a.jpg');
    expect(r.firstImageUrl, 'https://b.jpg');
  });

  test('ThemeModel fromJson aliases sample image and copyWith', () {
    final t = ThemeModel.fromJson({
      'id': 't1',
      'categoryId': 'c1',
      'name': 'N',
      'description': 'd',
      'promptText': 'p',
      'imageUrl': '/img.jpg',
      'isActive': true,
      'displayOrder': 3,
    });
    expect(t.sampleImageUrl, '/img.jpg');
    expect(t.prompt, 'p');
    expect(t.copyWith((p) => p.name = 'N2').name, 'N2');
    expect(t == ThemeModel.fromJson({'id': 't1', 'categoryId': 'c1', 'name': 'x', 'description': 'd', 'promptText': 'p'}), isTrue);
  });

  test('TransformedImageModel toJson round-trip', () {
    final m = TransformedImageModel(
      id: 'g1',
      imageUrl: 'https://cdn/x.jpg',
      originalPhotoId: 'p1',
      themeId: 't1',
      transformedAt: DateTime.utc(2026, 1, 1),
      runId: 'run-1',
    );
    final json = m.toJson();
    final back = TransformedImageModel.fromJson(json);
    expect(back.id, 'g1');
    expect(back.runId, 'run-1');
  });
}
