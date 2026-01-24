import 'app_config.dart';

class AppConstants {
  // API Configuration
  static const String kBaseUrl = AppConfig.baseUrl;
  // Increased timeout for image uploads and AI generation
  // Image uploads can take 5-15s, AI generation can take 10-60s
  static const Duration kApiTimeout = Duration(seconds: 120);
  
  // Longer timeout for AI generation specifically
  static const Duration kAiGenerationTimeout = Duration(seconds: 180);

  // Image Configuration
  static const int kImageQuality = 85;
  static const int kMaxImageWidth = 1920;
  static const int kMaxImageHeight = 1080;

  // UI Constants
  static const double kButtonHeight = 48.0;
  static const double kTabletBreakpoint = 600.0;
  static const double kTouchTargetSize = 48.0;
  static const String kContinueButtonText = 'Continue';

  // Routes
  static const String kRouteSlideshow = '/';
  static const String kRouteTerms = '/terms';
  static const String kRouteHome = '/theme-selection';
  static const String kRouteCapture = '/capture';
  static const String kRouteReview = '/review';
  static const String kRouteResult = '/result';
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

