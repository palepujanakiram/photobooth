import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';

import 'app_config.dart';
import 'app_runtime_config.dart';

class AppConstants {
  // Branding
  static const String kBrandName = 'Fotozen AI';
  static const String kBrandAppTitle = 'Fotozen AI Photo Booth';
  /// Wordmark used on terms/thank-you screens.
  static const String kBrandLogoAsset = 'lib/images/fotozen_wordmark.png';

  // API Configuration
  static const String kBaseUrl = AppConfig.baseUrl;
  // Extended timeout for image uploads and AI generation
  // Set to 5 minutes to handle slower networks and extended processing times
  static const Duration kApiTimeout = Duration(seconds: 300);

  /// Capture-screen PATCH upload (shorter than [kApiTimeout] so the UI does not
  /// sit on "Processing Your Photo" for minutes when the network fails).
  static const Duration kSessionUploadTimeout = Duration(seconds: 90);

  /// Best-effort `/api/preprocess-image` wait; on timeout the upload still succeeds
  /// with a fallback person count (solo themes on web).
  static const Duration kPreprocessTimeout = Duration(seconds: 30);
  
  // Timeout for AI generation (same as general timeout)
  static const Duration kAiGenerationTimeout = Duration(seconds: 300);

  /// Fallback when `/api/settings` omits or invalidates `parallelImageCount`.
  /// Server-driven value chooses POST `/api/generate-image` (when **1**) vs
  /// GET `/api/generate-stream-parallel` (when **> 1**); see [ApiService.generateImages].
  static const int kAiParallelGenerationCount = 1;

  /// Upper bound for `parallelImageCount` from settings (client-side sanity only).
  static const int kMaxParallelImageSlots = 12;

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

  /// [SharedPreferences] key: theme list uses card grid vs carousel on Select Theme.
  static const String kPrefsThemeSelectionCardLayout = 'theme_selection_use_card_layout';

  /// [SharedPreferences] key: carousel auto-advances when idle on Select Theme (default off).
  static const String kPrefsThemeCarouselAutoScroll = 'theme_carousel_auto_scroll_v1';

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

  /// Time between automatic carousel advances when the user is idle.
  static const Duration kThemeCarouselAutoScrollInterval =
      Duration(seconds: 5);

  /// Idle time after the user interacts (tap carousel, thumb, or grid) before
  /// auto-scroll resumes; timer phase resets so the next advance is a full
  /// [kThemeCarouselAutoScrollInterval] away.
  static const Duration kThemeCarouselAutoScrollPauseDuration =
      Duration(seconds: 8);

  /// Capture / preview card: max width as a fraction of screen width (landscape aligns ~theme carousel hero ~0.42–0.44).
  static const double kCapturePreviewCardMaxWidthFractionLandscape = 0.44;

  /// Capture / preview card: max width in portrait (leave side margins).
  static const double kCapturePreviewCardMaxWidthFractionPortrait = 0.92;

  /// Capture / preview card: max height as fraction of screen height (landscape kiosks — avoid a full-height tower).
  static const double kCapturePreviewCardMaxHeightFractionLandscape = 0.50;

  static const double kCapturePreviewCardMaxHeightFractionPortrait = 0.58;

  /// Phone portrait: allow more vertical space for the capture card than [kCapturePreviewCardMaxHeightFractionPortrait]
  /// (theme/kiosk value) so preview matches the usable viewport instead of a short strip.
  static const double kCapturePreviewCardMaxHeightFractionPhonePortrait = 0.78;

  /// BEHOLD single-result hero when output aspect is unknown (typical AI / kiosk output).
  static const double kBeholdSingleResultDefaultAspectRatio = 3 / 2;

  /// DNP-style print sizes for network printer API.
  static const String kPrintSizePortrait4x6 = 's4x6';
  static const String kPrintSizeLandscape6x4 = 's6x4';

  /// BEHOLD single-result hero: width cap on landscape / desktop (wider than capture kiosk).
  static const double kBeholdResultCardMaxWidthFractionLandscape = 0.52;

  /// BEHOLD single-result hero: height cap on landscape (taller than capture 0.50).
  static const double kBeholdResultCardMaxHeightFractionLandscape = 0.62;

  /// BEHOLD single-result hero: use nearly all of the Expanded slot above the footer.
  static const double kBeholdResultCardSlotHeightFraction = 0.98;

  /// On Generate Photo, generated-image cards scale to this factor when toggled (tap again restores 1.0).
  static const double kGeneratePhotoZoomedScale = 1.3;
  static const String kContinueButtonText = 'Continue';

  /// When true (from `/api/settings` → `showGenerationCommentary`), enables debug HUD
  /// and applies tighter RAM tuning for legacy ~2 GB Android TV / kiosk boxes.
  ///
  /// **Production kiosks:** target **4 GB RAM**; use default (non-commentary) thresholds
  /// in [LowMemoryMonitor] (~400 MB free system, ~800 MB app RSS).
  ///
  /// **Web:** always `false` — commentary there only enables logging/debug UI; kiosk RAM
  /// tuning would shrink [ImageCache] during capture/upload and block navigation.
  static bool get kLowMemoryKioskMode =>
      !kIsWeb && AppRuntimeConfig.instance.showGenerationCommentary;

  /// Extra delay after releasing a [CameraController] before opening the next (ms).
  /// Gives CameraX / HAL time to free buffers on slow 2 GB TV boxes when switching cams.
  static int get kCameraDisposeToReopenDelayMs =>
      kLowMemoryKioskMode ? 160 : 100;

  /// Camera / kiosk (operational — not enforced in code):
  /// - A short RAM spike when opening the camera is normal (native preview buffers).
  /// - Android uses a **vendored** `camera_android_camerax` fork: preview/ImageAnalysis run
  ///   one [ResolutionPreset] **below** still capture to save preview RAM; see
  ///   `packages/camera_android_camerax/lib/src/android_camera_camerax.dart`.
  /// - HDMI capture cards / UVC: still use [ResolutionPreset.high] in code (not max) to reduce
  ///   preview vs JPEG mismatch; enable **clean HDMI** on the DSLR and match 1080p progressive when possible.
  /// - Prefer powered USB hubs and one external webcam; avoid enumerating many unused devices.
  /// - Close other apps using the camera; reboot kiosk if enumeration hangs after OOM.
  /// - For extreme OOM only, consider `android:largeHeap="true"` in the Android manifest
  ///   (trade-off: harder to catch real leaks).

  /// When true, shows an overlay above Cancel/Continue with photo metadata (size, format).
  /// Off when [kLowMemoryKioskMode] is true (avoids full-image decode on the UI isolate).
  static bool get kShowCapturedPhotoMetadataOverlay => false;

  /// Theme image disk cache ceiling (MB); lower on kiosk.
  static int get kThemeDiskCacheMaxSizeMB =>
      kLowMemoryKioskMode ? 40 : 100;

  /// Flutter in-memory [ImageCache] — max entries when [kLowMemoryKioskMode].
  static int get kFlutterImageCacheMaxCount =>
      kLowMemoryKioskMode ? 40 : 100;

  /// Flutter in-memory [ImageCache] — max total bytes when [kLowMemoryKioskMode].
  static int get kFlutterImageCacheMaxBytes => kLowMemoryKioskMode
      ? 50 * 1024 * 1024
      : 100 * 1024 * 1024;

  /// Gallery picker JPEG quality before normalization (lower = less work / smaller temp file).
  static int get kGalleryPickerImageQuality =>
      kLowMemoryKioskMode ? 85 : 95;

  /// When true (with `showGenerationCommentary`), shows native camera details on Capture Photo.
  /// **Off on web** — `camera_native_details` / layout differs; avoids extra work after capture.
  static bool get kShowNativeCameraInfoPane =>
      !kIsWeb && AppRuntimeConfig.instance.showGenerationCommentary;

  /// When true, shows the Print & Share Options section (Printer IP, Silent Print, Print, Share) on Complete Payment / Result screen.
  static const bool kShowResultPrintSection = false;

  /// When true, full-screen loaders show status text, elapsed timer, subtitle,
  /// and current-process line (`kDebugMode` or `showGenerationCommentary`).
  static bool get kshowDebugInfo =>
      kDebugMode || AppRuntimeConfig.instance.showGenerationCommentary;

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
  static const int kCaptureCountdownSeconds = 5;

  /// POSE screen: return to Terms after this much user inactivity (live feed or review).
  static const Duration kCaptureScreenIdleResetDuration = Duration(minutes: 5);

  /// How long the idle-reset snackbar stays visible before navigating away.
  static const Duration kCaptureScreenIdleResetSnackDuration =
      Duration(seconds: 3);

  /// Pause after showing the idle-reset snackbar so the guest can read it.
  static const Duration kCaptureScreenIdleResetSnackDelay =
      Duration(milliseconds: 2500);

  /// On-screen debug HUD: Logs panel, Perf trace (+ E2E summary), RAM / JS heap.
  /// Driven by `/api/settings` → `showGenerationCommentary` (not [kEnableLogOutput]).
  static bool get kShowDebugHud =>
      AppRuntimeConfig.instance.showGenerationCommentary;

  // Console / API logging (not the on-screen HUD). On in [kDebugMode] by default;
  // release off unless `--dart-define=ENABLE_LOG_OUTPUT=true`. Force off with
  // `--dart-define=ENABLE_LOG_OUTPUT=false`.
  @visibleForTesting
  static bool? testEnableLogOutputOverride;

  static bool get kEnableLogOutput {
    if (testEnableLogOutputOverride != null) {
      return testEnableLogOutputOverride!;
    }
    const env = String.fromEnvironment('ENABLE_LOG_OUTPUT');
    if (env == 'true') return true;
    if (env == 'false') return false;
    return kDebugMode;
  }

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
  /// Branded splash: kiosk check, optional theme preload, then terms.
  static const String kRouteSplash = '/splash';
  static const String kRouteTerms = '/terms';
  static const String kRouteHome = '/theme-selection';
  static const String kRouteCapture = '/capture';
  /// Kiosk: choose occasion frame (or none) after theme, before generation.
  static const String kRouteFrameSelect = '/frame-select';
  static const String kRouteGenerate = '/generate';
  static const String kRouteGenerateProgress = '/generate-progress';
  static const String kRouteReview = '/review';
  static const String kRouteResult = '/result';
  static const String kRouteThankYou = '/thank-you';
  /// Post-payment QR bridge + optional print/share actions (kiosk).
  static const String kRouteQrShare = '/qr-share';
  /// Push [WebViewScreen] (full-screen, close button only; no app bar) using
  /// `arguments`: a URL [String], or a [Map] with `url` ([String]).
  static const String kRouteWebView = '/webview';

  // Staff routes
  static const String kRouteStaffLogin = '/staff/login';
  static const String kRouteStaffPayments = '/staff/payments';

  // Error Messages
  static const String kErrorCameraPermission = 'Camera permission denied';
  static const String kErrorCameraInitialization =
      'Failed to initialize camera';
  static const String kErrorPhotoCapture = 'Failed to capture photo';
  static const String kErrorApiCall = 'Failed to process request';
  static const String kErrorNetwork = 'Network error occurred';
  static const String kErrorUnknown = 'An unexpected error occurred';
}

