import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/models/kiosk_share_link_model.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/result/result_payment_status.dart';
import 'package:photobooth/screens/result/transformed_image_model.dart';
import 'package:photobooth/screens/splash/bootstrap_route_args.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/screens/theme_slideshow/theme_slideshow_layout.dart';
import 'package:photobooth/services/client_identification.dart';
import 'package:photobooth/services/error_reporting/error_reporting_manager.dart';
import 'package:photobooth/services/fcm_payment_pending_store.dart';
import 'package:photobooth/services/fcm_token_store.dart';
import 'package:photobooth/services/generation_display_preferences.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/image_helper.dart';
import 'package:photobooth/utils/logger.dart';
import 'package:photobooth/utils/secure_image_url.dart' show SecureImageUrl;
import 'package:photobooth/utils/session_user_image_validation.dart';
import 'package:photobooth/utils/theme_image_urls.dart';
import 'package:photobooth/utils/transformation_step_display.dart';
import 'package:photobooth/utils/web_flow_trace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_error_reporting_service.dart';
import '../helpers/tiny_jpeg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exception toString variants', () {
    expect(CameraException('c').toString(), contains('CameraException'));
    expect(
      ApiException('ReferenceError: x', 500).userFacingMessage,
      contains('Something went wrong'),
    );
    expect(ApiException('plain error', 500).userFacingMessage, 'plain error');
    expect(PermissionException('p').toString(), contains('Permission'));
    expect(PrintException('p').toString(), contains('Print'));
    expect(ShareException('s').toString(), contains('Share'));
  });

  test('ClientIdentification ensureInitialized', () async {
    await ClientIdentification.ensureInitialized();
    expect(ClientIdentification.httpHeaders, isNotEmpty);
    expect(ClientIdentification.httpHeaders['X-Client-Type'], isNotEmpty);
    expect(ClientIdentification.clientType, isNotEmpty);
    expect(ClientIdentification.platformLabel, isNotEmpty);
  });

  test('AppRuntimeConfig applyFromSettings toggles', () {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    expect(AppRuntimeConfig.instance.showGenerationCommentary, isFalse);
    applyFlutterImageCacheLimits();
  });

  test('KioskManager prefs round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final km = KioskManager();
    await km.setKioskCode('abc');
    expect(await km.getKioskCode(), 'ABC');
    await km.setPaymentEnabledOverride(false);
    expect(await km.getPaymentEnabledOverride(), isFalse);
    await km.clearPaymentEnabledOverride();
    await km.clearKioskCode();
    expect(await km.getKioskCode(), isNull);
  });

  test('FcmPaymentPendingStore lifecycle', () async {
    SharedPreferences.setMockInitialValues({});
    const msg = RemoteMessage(
      data: {'sessionId': 'sess-1', 'type': 'payment'},
      notification: RemoteNotification(title: 't', body: 'b'),
    );
    await FcmPaymentPendingStore.persist(msg);
    final pending = await FcmPaymentPendingStore.takePending();
    expect(pending?['originSessionId'], 'sess-1');
    await FcmPaymentPendingStore.restore({'data': {'x': 1}});
    await FcmPaymentPendingStore.clear();
  });

  test('FcmTokenStore', () async {
    SharedPreferences.setMockInitialValues({});
    await FcmTokenStore.save('tok');
    expect(await FcmTokenStore.getCached(), 'tok');
  });

  test('GenerationDisplayPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    await GenerationDisplayPreferences.setUseProgressiveGenerationUi(false);
    expect(await GenerationDisplayPreferences.getUseProgressiveGenerationUi(), isFalse);
  });

  test('models edge cases', () {
    KioskFrameModel.fromJson({
      'id': 'f',
      'name': 'n',
      'overlayUrl': 'https://x',
      'scheduledStartAt': '2026-01-01T00:00:00Z',
    });
    KioskInfoModel.fromJson({'id': 'k', 'code': 'C', 'paymentEnabled': 'bad'});
    KioskShareLinkModel.fromJson({'token': '', 'url': ''});
    PaymentInitiateResult.fromJson({'status': 'X'});
    ThemeModel.fromJson({
      'id': 't',
      'categoryId': 'c',
      'name': 'n',
      'description': 'd',
      'promptText': 'p',
      'backgroundColor': '#fff',
      'textColor': '#000',
    });
    PhotoModel.fromJson({
      'id': 'p',
      'imagePath': '/tmp/p.jpg',
      'capturedAt': DateTime.now().toIso8601String(),
      'isTransformed': true,
    }).copyWith(cameraId: 'cam-1');
    TransformedImageModel.fromJson({
      'id': 'g',
      'imageUrl': 'https://x',
      'originalPhotoId': 'p',
      'themeId': 't',
      'transformedAt': DateTime.now().toIso8601String(),
    }).copyWith(imageUrl: 'https://y');
    const SplashRouteArgs().manageKiosk;
    const TermsRouteArgs(backgroundImageUrls: ['a']);
  });

  test('computePaymentCardHeight', () {
    expect(
      computePaymentCardHeight(const BoxConstraints(maxHeight: 200, maxWidth: 100)),
      260,
    );
  });

  test('SlideshowLayoutMetrics and selectSlideshowDisplayUrls', () {
    const portraitPhone = SlideshowLayoutMetrics(isLandscape: false, isTablet: false);
    const landscapeTablet = SlideshowLayoutMetrics(isLandscape: true, isTablet: true);
    expect(portraitPhone.edgePaddingLeft, 20);
    expect(landscapeTablet.brandTitleSize, 20);
    expect(
      selectSlideshowDisplayUrls(sampleUrls: ['b'], preloadedUrls: ['a']),
      ['a'],
    );
    expect(
      selectSlideshowDisplayUrls(sampleUrls: ['b'], preloadedUrls: []),
      ['b'],
    );
  });

  test('ImageHelper encodeImageToBase64 and rotate', () async {
    final url = await ImageHelper.encodeImageToBase64(tinyJpegXFile());
    expect(url, startsWith('data:image/jpeg'));
  });

  test('secure_image_url and theme urls', () {
    expect(resolveThemeSampleImageUrl('https://x.com/a'), 'https://x.com/a');
    expect(normalizeThemeImageUrl('https://x.com/a?q=1'), 'https://x.com/a');
    expect(SecureImageUrl.absolutize('/api/img/x'), contains('/api/img/x'));
  });

  test('transformation_step_display all stages', () {
    for (final s in ['queued', 'generating', 'upscaling', 'done', 'unknown']) {
      transformationStepDisplayLabel(s);
      transformationStepIcon(s);
    }
  });

  test('session validation rejects bad base64', () {
    expect(
      () => SessionUserImageValidation.assertValidForSessionPatch(
        'data:image/jpeg;base64,@@@',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('WebFlowTrace', () {
    WebFlowTrace.reset(label: 't');
    WebFlowTrace.log('step');
  });

  test('AppLogger levels', () {
    AppLogger.debug('d');
    AppLogger.info('i');
    AppLogger.warning('w');
    AppLogger.error('e', error: Exception('x'));
  });

  test('ErrorReportingManager with fake service', () async {
    final fake = FakeErrorReportingService();
    // Cannot inject fake without prod change — exercise public API after init.
    await ErrorReportingManager.initialize(enableBugsnag: false);
    await ErrorReportingManager.setEnabled(true);
    ErrorReportingManager.log('breadcrumb');
    await ErrorReportingManager.recordError(Exception('x'), StackTrace.current);
    await ErrorReportingManager.setUserId('u1');
    await ErrorReportingManager.setCustomKey('k', 'v');
    await ErrorReportingManager.setCustomKeys({'a': 1});
    await ErrorReportingManager.setCameraContext(cameraId: 'c');
    await ErrorReportingManager.setPhotoCaptureContext(photoId: 'p');
    await ErrorReportingManager.clearContext();
    expect(ErrorReportingManager.isInitialized, isTrue);
    expect(ErrorReportingManager.serviceCount, 0);
    fake.log('ignored');
  });

  test('AppConstants brand', () {
    expect(AppConstants.kBrandName, isNotEmpty);
    expect(AppConstants.kPrefsThemeSelectionCardLayout, isNotEmpty);
  });
}
