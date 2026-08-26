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
  test('AppSettingsModel.fromJson parses payment collection timing', () {
    final m = AppSettingsModel.fromJson({
      'paymentCollectionTiming': 'before_generation',
    });
    expect(m.paymentCollectionTiming, 'before_generation');
  });

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

  test('AppSettingsModel.fromJson parses commentary and thermal flags', () {
    final m = AppSettingsModel.fromJson({
      'showGenerationCommentary': true,
      'thermalSafeMode': true,
    });
    expect(m.showGenerationCommentary, isTrue);
    expect(m.thermalSafeMode, isTrue);
  });

  test('AppSettingsModel.fromJson parses receipt printer fields', () {
    final m = AppSettingsModel.fromJson({
      'receiptPrinterEnabled': true,
      'receiptPrinterHost': '192.168.2.43',
      'receiptPrinterPort': 9100,
    });
    expect(m.receiptPrinterEnabled, isTrue);
    expect(m.receiptPrinterHost, '192.168.2.43');
    expect(m.receiptPrinterPort, 9100);
  });

  test('AppSettingsModel.fromJson parses camera sidecar fields', () {
    final m = AppSettingsModel.fromJson({
      'cameraEnabled': true,
      'cameraSidecarHost': '172.16.4.20',
      'cameraSidecarPort': 8791,
      'cameraSidecarPath': '/',
    });
    expect(m.cameraEnabled, isTrue);
    expect(m.cameraSidecarHost, '172.16.4.20');
    expect(m.cameraSidecarPort, 8791);
    expect(m.cameraSidecarPath, '/');
  });

  test('AppSettingsModel.fromJson parses offlineCashPins', () {
    final m = AppSettingsModel.fromJson({
      'offlineCashPins': ['1357', '9999', 'nope', 2468],
    });
    expect(m.offlineCashPins, ['1357', '9999', '2468']);
  });

  test('AppSettingsModel.fromJson parses receiptMerchant', () {
    final m = AppSettingsModel.fromJson({
      'receiptMerchant': {
        'legalName': 'Sri Sarani Ventures Pvt Ltd',
        'gstin': '36AAAAA0000A1Z5',
        'gstRateBps': 1800,
        'gstSplitMode': 'cgst_sgst',
        'hsnSac': '998383',
        'kioskCode': 'ODEON-01',
      },
    });
    expect(m.receiptMerchant?.gstin, '36AAAAA0000A1Z5');
    expect(m.receiptMerchant?.merchantName, contains('Sri Sarani'));
    expect(m.receiptMerchant?.gstRateBps, 1800);
  });

  test('KioskInfoModel.isValid requires id and code', () {
    expect(
      KioskInfoModel.fromJson({'id': 'k1', 'code': 'ABC'}).isValid,
      isTrue,
    );
    expect(KioskInfoModel.fromJson({'id': '', 'code': 'x'}).isValid, isFalse);
  });

  test('KioskInfoModel toJson round-trips through fromJson', () {
    const original = KioskInfoModel(
      id: 'k1',
      code: 'ABC',
      name: 'Lobby',
      location: 'Floor 1',
      accountId: 'a1',
      paymentEnabled: false,
      classicPhotosEnabled: false,
      initialPrice: 100,
      additionalPrintPrice: 50,
      regenerationPrice: 75,
      operatingMode: KioskInfoModel.operatingModeOffline,
    );
    final again = KioskInfoModel.fromJson(original.toJson());
    expect(again.id, original.id);
    expect(again.code, original.code);
    expect(again.name, original.name);
    expect(again.location, original.location);
    expect(again.accountId, original.accountId);
    expect(again.paymentEnabled, original.paymentEnabled);
    expect(again.classicPhotosEnabled, original.classicPhotosEnabled);
    expect(again.initialPrice, original.initialPrice);
    expect(again.additionalPrintPrice, original.additionalPrintPrice);
    expect(again.regenerationPrice, original.regenerationPrice);
    expect(again.operatingMode, original.operatingMode);
  });

  test('KioskInfoModel parses price overrides', () {
    final m = KioskInfoModel.fromJson({
      'id': 'k1',
      'code': 'ABC',
      'initialPrice': 150,
      'additionalPrintPrice': '60',
      'regenerationPrice': 80,
      'paymentEnabled': true,
    });
    expect(m.initialPrice, 150);
    expect(m.additionalPrintPrice, 60);
    expect(m.regenerationPrice, 80);
    expect(m.paymentEnabled, isTrue);
    expect(m.classicPhotosEnabled, isTrue);
  });

  test('KioskInfoModel classicPhotosEnabled defaults and parses false', () {
    expect(
      KioskInfoModel.fromJson({'id': 'k1', 'code': 'ABC'}).classicPhotosEnabled,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'classicPhotosEnabled': false,
      }).classicPhotosEnabled,
      isFalse,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'classicPhotosEnabled': true,
      }).classicPhotosEnabled,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'classic_photos_enabled': true,
      }).classicPhotosEnabled,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'classicPhotosEnabled': 'false',
      }).classicPhotosEnabled,
      isFalse,
    );
    for (final flag in ['true', '1', 'yes', 'on', ' TRUE ']) {
      expect(
        KioskInfoModel.fromJson({
          'id': 'k1',
          'code': 'ABC',
          'classicPhotosEnabled': flag,
        }).classicPhotosEnabled,
        isTrue,
        reason: 'string flag "$flag" should enable Classic',
      );
    }
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'classicPhotosEnabled': <String>['weird'],
      }).classicPhotosEnabled,
      isTrue,
      reason: 'unknown shape prefers enabling Classic',
    );
  });

  test('KioskInfoModel operatingMode defaults online and parses offline', () {
    expect(
      KioskInfoModel.fromJson({'id': 'k1', 'code': 'ABC'}).operatingMode,
      KioskInfoModel.operatingModeOnline,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': 'offline',
      }).isOperatingModeOffline,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operating_mode': 'OFFLINE',
      }).isOperatingModeOffline,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': true,
      }).isOperatingModeOffline,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': 0,
      }).isOperatingModeOffline,
      isFalse,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': 1,
      }).isOperatingModeOffline,
      isTrue,
    );
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': false,
      }).isOperatingModeOffline,
      isFalse,
    );
    for (final flag in ['off', 'true', '1', 'yes']) {
      expect(
        KioskInfoModel.fromJson({
          'id': 'k1',
          'code': 'ABC',
          'operatingMode': flag,
        }).isOperatingModeOffline,
        isTrue,
        reason: '"$flag" should mean offline',
      );
    }
    expect(
      KioskInfoModel.fromJson({
        'id': 'k1',
        'code': 'ABC',
        'operatingMode': 'online',
      }).isOperatingModeOffline,
      isFalse,
    );
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

  test('ThemeModel.fromJson tolerates null optional fields', () {
    final t = ThemeModel.fromJson({
      'id': 't2',
      'name': 'Solo',
      'promptText': 'prompt',
    });
    expect(t.categoryId, '');
    expect(t.description, '');
    expect(t.name, 'Solo');
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
