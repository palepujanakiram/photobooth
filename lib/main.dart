import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'screens/theme_slideshow/theme_slideshow_view.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/result/result_view.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';
import 'services/error_reporting/error_reporting_manager.dart';
import 'services/file_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Bugsnag first
  await bugsnag.start(apiKey: '73ebb791c48ae8c4821b511fb286ca23');

  // Fire-and-forget cleanup of temp images
  FileHelper.cleanupTempImages();
    
  // Initialize ErrorReportingManager (uses Bugsnag)
  await ErrorReportingManager.initialize(
    enableBugsnag: true,
  );

  // Set up Flutter error handler with filtering
  FlutterError.onError = (errorDetails) {
    // Filter out non-fatal image decoding errors
    // These are handled by Image.errorBuilder widgets
    final errorString = errorDetails.exception.toString().toLowerCase();
    if (errorString.contains('image decoding') ||
        errorString.contains('failed to submit image decoding command buffer') ||
        errorString.contains('codec failed to produce an image') ||
        errorString.contains('failed to load network image')) {
      // Log to console in debug mode but don't report to Bugsnag
      if (kDebugMode) {
        AppLogger.debug('Image loading error (non-fatal, handled by UI): ${errorDetails.exception}');
      }
      return;
    }
    
    ErrorReportingManager.recordError(
      errorDetails.exception,
      errorDetails.stack,
      reason: 'Flutter Fatal Error',
      fatal: true,
    );
    
    // Also log to console in debug mode
    if (kDebugMode) {
      AppLogger.error(
        'Flutter Fatal Error: ${errorDetails.exception}',
        error: errorDetails.exception,
        stackTrace: errorDetails.stack,
      );
    }
  };

  // Pass all uncaught asynchronous errors to ErrorReportingManager with filtering
  PlatformDispatcher.instance.onError = (error, stack) {
    // Filter out non-fatal image decoding errors
    // These are handled by Image.errorBuilder widgets
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('image decoding') ||
        errorString.contains('failed to submit image decoding command buffer') ||
        errorString.contains('codec failed to produce an image') ||
        errorString.contains('failed to load network image')) {
      // Log to console in debug mode but don't report to Bugsnag
      if (kDebugMode) {
        AppLogger.debug('Image loading error (non-fatal, handled by UI): $error');
      }
      return true; // Mark as handled
    }
    
    ErrorReportingManager.recordError(
      error,
      stack,
      reason: 'Uncaught Async Error',
      fatal: true,
    );
    
    // Also log to console in debug mode
    if (kDebugMode) {
      AppLogger.error(
        'Uncaught Error: $error',
        error: error,
        stackTrace: stack,
      );
    }
    return true;
  };

  if (kDebugMode) {
    print('✅ Error reporting initialized successfully');
    print('   Active services: ${ErrorReportingManager.serviceCount}');
    print('   - Bugsnag: enabled');
  }
  
  runApp(const PhotoBoothApp());
}

class PhotoBoothApp extends StatelessWidget {
  const PhotoBoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
      ],
      child: CupertinoApp(
        title: 'Photo Booth',
        debugShowCheckedModeBanner: false,
        // Remove hardcoded theme to allow dark mode support
        // The app will automatically use system theme (light/dark)
        initialRoute: AppConstants.kRouteSlideshow,
        routes: {
          AppConstants.kRouteSlideshow: (context) =>
              const ThemeSlideshowScreen(),
          AppConstants.kRouteTerms: (context) =>
              const TermsAndConditionsScreen(),
          AppConstants.kRouteHome: (context) => const ThemeSelectionScreen(),
          AppConstants.kRouteCapture: (context) => const PhotoCaptureScreen(),
          AppConstants.kRouteReview: (context) => const PhotoReviewScreen(),
          AppConstants.kRouteResult: (context) => const ResultScreen(),
        },
      ),
    );
  }
}
