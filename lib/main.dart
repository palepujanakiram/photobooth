import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'screens/theme_slideshow/theme_slideshow_view.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/result/result_view.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp();
    
    // Enable Crashlytics collection
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      // Also log to console in debug mode
      if (kDebugMode) {
        AppLogger.error(
          'Flutter Fatal Error: ${errorDetails.exception}',
          error: errorDetails.exception,
          stackTrace: errorDetails.stack,
        );
      }
    };
    
    // Pass all uncaught asynchronous errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
      print('✅ Firebase Crashlytics initialized successfully');
    }
  } catch (e) {
    // Firebase initialization failed - app will still work without Crashlytics
    if (kDebugMode) {
      print('⚠️ Firebase initialization failed: $e');
      print('⚠️ App will continue without Crashlytics');
      print('💡 To fix: Run "flutter pub global activate flutterfire_cli && flutterfire configure"');
    }
    
    // Set up basic error logging without Crashlytics
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
