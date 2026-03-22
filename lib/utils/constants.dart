import 'app_config.dart';

class AppConstants {
  // API Configuration
  static const String kBaseUrl = AppConfig.baseUrl;
  // Extended timeout for image uploads and AI generation
  // Set to 5 minutes to handle slower networks and extended processing times
  static const Duration kApiTimeout = Duration(seconds: 300);
  
  // Timeout for AI generation (same as general timeout)
  static const Duration kAiGenerationTimeout = Duration(seconds: 300);

  // Image Configuration
  static const int kImageQuality = 85;
  static const int kMaxImageWidth = 1920;
  static const int kMaxImageHeight = 1080;

  // UI Constants
  static const double kButtonHeight = 48.0;
  static const double kTabletBreakpoint = 600.0;
  static const double kTouchTargetSize = 48.0;
  static const String kContinueButtonText = 'Continue';

  /// When true, shows an overlay above Cancel/Continue with photo metadata (size, format).
  static const bool kShowCapturedPhotoMetadataOverlay = true;

  /// When true, shows the native camera info pane (preview size, active array, zoom, etc.) on Capture Photo screen.
  static const bool kShowNativeCameraInfoPane = false;

  /// When true, shows the Print & Share Options section (Printer IP, Silent Print, Print, Share) on Complete Payment / Result screen.
  static const bool kShowResultPrintSection = false;

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
  /// [AppConfig.baseUrl]/terms; replace with any absolute URL if hosted elsewhere.
  static const String kTermsAndConditionsUrl = '${AppConfig.baseUrl}/terms';

  // Routes
  static const String kRouteSlideshow = '/';
  static const String kRouteTerms = '/terms';
  static const String kRouteHome = '/theme-selection';
  static const String kRouteCapture = '/capture';
  static const String kRouteGenerate = '/generate';
  static const String kRouteReview = '/review';
  static const String kRouteResult = '/result';
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

