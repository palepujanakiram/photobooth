import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
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

Future<void> main() async {
  await bugsnag.start(apiKey: '73ebb791c48ae8c4821b511fb286ca23');
  
  WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize Firebase with error handling
    try {
      await Firebase.initializeApp();
      
      // Initialize ErrorReportingManager (uses both Crashlytics and Bugsnag)
      // Bugsnag is enabled by default for all environments
      await ErrorReportingManager.initialize(
        enableCrashlytics: true,
        enableBugsnag: true,  // Always enabled by default
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
        print('   - Crashlytics: enabled');
        print('   - Bugsnag: enabled');
      }
    } catch (e) {
      // Firebase initialization failed - app will still work without error reporting
      if (kDebugMode) {
        print('⚠️ Firebase initialization failed: $e');
        print('⚠️ App will continue with Bugsnag only');
        print('💡 To fix: Run "flutter pub global activate flutterfire_cli && flutterfire configure"');
      }
      
      // Set up basic error logging without error reporting
      FlutterError.onError = (errorDetails) {
        if (kDebugMode) {
          AppLogger.error(
            'Flutter Fatal Error: ${errorDetails.exception}',
            error: errorDetails.exception,
            stackTrace: errorDetails.stack,
          );
        }
      };
      
      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) {
          AppLogger.error(
            'Uncaught Error: $error',
            error: error,
            stackTrace: stack,
          );
        }
        return true;
      };
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
