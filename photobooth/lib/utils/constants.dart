import 'package:flutter/widgets.dart';

import 'app_config.dart';

class AppConstants {
  // Branding
  static const String kBrandName = 'Fotozen AI';
  static const String kBrandAppTitle = 'Fotozen AI Photo Booth';
  static const String kBrandLogoAsset = 'lib/images/fotozen_ai_logo.png';

  // API Configuration
  static const String kBaseUrl = AppConfig.baseUrl;
  // Extended timeout for image uploads and AI generation
  // Set to 5 minutes to handle slower networks and extended processing times
  static const Duration kApiTimeout = Duration(seconds: 300);
  
  // Timeout for AI generation (same as general timeout)
  static const Duration kAiGenerationTimeout = Duration(seconds: 300);

  /// `count` for GET `/api/generate-stream-parallel`. Use **1** when each UI action
  /// should produce a single image; use **3** (or more) only if the screen offers
  /// multiple parallel style options in one request.
  static const int kAiParallelGenerationCount = 1;

  /// Fallback when `/api/settings` omits `initialPrice` / `additionalPrintPrice`.
  static const int kDefaultInitialPrintPrice = 100;
  static const int kDefaultAdditionalPrintPrice = 50;

  /// Fallback when `/api/settings` omits `maxRegenerations` (total generation slots on Generate screen).
  static const int kDefaultMaxRegenerations = 3;

  /// Fallback when `/api/settings` omits `printerHost`.
  static const String kDefaultPrinterHost = '192.168.2.108';

  // Image Configuration
  static const int kImageQuality = 85;
  static const int kMaxImageWidth = 1920;
  static const int kMaxImageHeight = 1080;

  // UI Constants
  static const double kButtonHeight = 48.0;
  static const double kTabletBreakpoint = 600.0;
  static const double kTouchTargetSize = 48.0;

  /// Width : height for theme/generate cards in **portrait** device orientation.
  /// Slightly shorter than raw 9:16 for legacy grid harmony.
  static const double kThemeSelectedCardAspectRatio = 3 / 4.5;

  /// Typical phone portrait capture & AI output (width : height). Use in **landscape**
  /// / kiosk layouts so card slots match portrait photos and avoid letterboxing.
  static const double kPortraitCaptureAspectRatio = 9 / 16;

  /// Center hero card in theme carousel: portrait UI uses [kThemeSelectedCardAspectRatio];
  /// landscape / kiosk uses [kPortraitCaptureAspectRatio] to match captured images.
  static double themeCardSlotAspectRatio(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape
        ? kPortraitCaptureAspectRatio
        : kThemeSelectedCardAspectRatio;
  }

  /// Non-center carousel pages: a touch wider than center for depth (landscape still portrait-shaped).
  static double themeCarouselSideAspectRatio(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape
        ? 9 / 15.5
        : 3 / 4;
  }

  /// Default [PageController.viewportFraction] for very wide layouts; phones use ~0.76 in code.
  static const double kThemeCarouselViewportFraction = 0.38;

  /// Peak scale of the centered card in the theme carousel 3D transform (clamped in carousel).
  static const double kThemeCarouselCenterMaxScale = 1.15;

  /// Pause duration after user taps a theme before auto-scroll resumes.
  static const Duration kThemeCarouselAutoScrollPauseDuration =
      Duration(seconds: 4);

  /// On Generate Photo, generated-image cards scale to this factor when toggled (tap again restores 1.0).
  static const double kGeneratePhotoZoomedScale = 1.3;
  static const String kContinueButtonText = 'Continue';

  /// When true, shows an overlay above Cancel/Continue with photo metadata (size, format).
  static const bool kShowCapturedPhotoMetadataOverlay = true;

  /// When true, shows the native camera info pane (preview size, active array, zoom, etc.) on Capture Photo screen.
  static const bool kShowNativeCameraInfoPane = false;

  /// When true, shows the Print & Share Options section (Printer IP, Silent Print, Print, Share) on Complete Payment / Result screen.
  static const bool kShowResultPrintSection = false;

  /// When true, full-screen loaders show status text, elapsed timer, subtitle, and current-process line.
  /// When false, only the spinner (and any optional loader hint) are shown so the panel height follows content.
  static const bool kshowDebugInfo = false;

  /// SharedPreferences key for camera preview rotation (0, 90, 180, 270 degrees).
  static const String kCameraPreviewRotationKey = 'camera_preview_rotation_degrees';

  /// Tracks whether preview rotation was explicitly chosen by the user.
  static const String kCameraPreviewRotationConfiguredKey =
      'camera_preview_rotation_configured';

  /// Used to migrate old preview-rotation workarounds when rotation logic changes.
  static const String kCameraPreviewRotationMigrationVersionKey =
      'camera_preview_rotation_migration_version';

  static const int kCameraPreviewRotationMigrationVersion = 2;

  /// Default preview rotation when no value is saved. One of 0, 90, 180, 270.
  static const int kCameraPreviewRotationDefault = 0;

  // Camera capture countdown (in seconds)
  static const int kCaptureCountdownSeconds = 3;

  // Logging
  // Controls console logs and breadcrumb logs (Bugsnag)
  static const bool kEnableLogOutput = false;

  /// Terms & Conditions page (WebView via [WebViewScreen]). Defaults to
  /// [AppConfig.baseUrl]/terms.
  ///
  /// **Performance:** If that URL serves the same heavy SPA shell (large JS bundle,
  /// Google Fonts CSS, etc.) as the main site, the WebView will feel slow until all
  /// assets load. For a fast legal page, host a **static** HTML document (or a
  /// minimal route) and point this constant at that URL instead.
  static const String kTermsAndConditionsUrl = '${AppConfig.baseUrl}/terms';

  // Routes
  static const String kRouteSlideshow = '/';
  static const String kRouteTerms = '/terms';
  static const String kRouteHome = '/theme-selection';
  static const String kRouteCapture = '/capture';
  static const String kRouteGenerate = '/generate';
  static const String kRouteReview = '/review';
  static const String kRouteResult = '/result';
  static const String kRouteThankYou = '/thank-you';
  /// Push [WebViewScreen] (full-screen, close button only; no app bar) using
  /// `arguments`: a URL [String], or a [Map] with `url` ([String]).
  static const String kRouteWebView = '/webview';

  // Error Messages
  static const String kErrorCameraPermission = 'Camera permission denied';
  static const String kErrorCameraInitialization =
      'Failed to initialize camera';
  static const String kErrorPhotoCapture = 'Failed to capture photo';
  static const String kErrorApiCall = 'Failed to process request';
  static const String kErrorNetwork = 'Network error occurred';
  static const String kErrorUnknown = 'An unexpected error occurred';
}

