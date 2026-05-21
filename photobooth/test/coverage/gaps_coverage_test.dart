import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/kiosk_share_link_model.dart';
import 'package:photobooth/models/parallel_generation_result.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/result/result_payment_status.dart';
import 'package:photobooth/screens/result/transformed_image_model.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/generation_display_preferences.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/theme_image_urls.dart';
import 'package:photobooth/utils/web_flow_trace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('model and util edge constructors', () {
    AppSettingsModel.fromJson({'showGenerationCommentary': false});
    KioskShareLinkModel.fromJson({'token': 't', 'url': 'u', 'longUrl': 'l'});
    PaymentInitiateResult.fromJson({'id': 'p', 'status': 'PENDING'});
    ParallelGenerationResult(
      imageUrlsBySlot: const [],
      success: false,
    ).preferredImageUrl;
    ThemeModel.fromJson({
      'id': 't',
      'categoryId': 'c',
      'name': 'n',
      'description': 'd',
      'promptText': 'p',
      'sampleImageUrl': 'https://cdn/s.jpg',
    });
    PhotoModel.fromJson({
      'id': 'p',
      'imagePath': '/x',
      'capturedAt': DateTime.now().toIso8601String(),
    });
    TransformedImageModel.fromJson({
      'id': 'g',
      'imageUrl': 'https://x',
      'originalPhotoId': 'p',
      'themeId': 't',
      'transformedAt': DateTime.now().toIso8601String(),
    });
    expect(resolveThemeSampleImageUrl(''), isNotEmpty);
    expect(normalizeThemeImageUrl('https://x.com/a?b=1'), 'https://x.com/a');
    WebFlowTrace.reset(label: 'test');
    WebFlowTrace.log('phase', 'detail');
    expect(
      computePaymentCardHeight(const BoxConstraints(maxHeight: 800)),
      800,
    );
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
  });

  test('GenerationDisplayPreferences round trip', () async {
    SharedPreferences.setMockInitialValues({});
    await GenerationDisplayPreferences.setUseProgressiveGenerationUi(true);
    expect(await GenerationDisplayPreferences.getUseProgressiveGenerationUi(), isTrue);
  });
}
