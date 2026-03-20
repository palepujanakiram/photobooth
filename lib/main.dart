import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'package:flutter_alice/alice.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'screens/theme_slideshow/theme_slideshow_view.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_generate/photo_generate_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/result/result_view.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';
import 'services/error_reporting/error_reporting_manager.dart';
import 'services/file_helper.dart';
import 'services/alice_inspector.dart';
import 'services/app_settings_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Do not preload cameras at startup. On devices with only LENS_FACING_EXTERNAL
  // cameras (e.g. RTC Mini PC), any camera plugin call triggers CameraX init and
  // repeated validation failures, which slows or blocks the main thread. Cameras
  // are loaded when the user opens the Capture screen (with timeout).

  // Initialize Bugsnag only when native plugin is available (iOS/Android; not on web/tests)
  if (!kIsWeb) {
    try {
      await bugsnag.start(
        apiKey: '73ebb791c48ae8c4821b511fb286ca23',
        enabledBreadcrumbTypes: const {
          BugsnagEnabledBreadcrumbType.error,
          BugsnagEnabledBreadcrumbType.navigation,
          BugsnagEnabledBreadcrumbType.request,
          BugsnagEnabledBreadcrumbType.state,
          BugsnagEnabledBreadcrumbType.user,
        },
        maxBreadcrumbs: 50,
      );
    } on MissingPluginException catch (_) {
      // Native Bugsnag plugin not available (e.g. unit tests, or platform not linked)
    }
  }

  // Fire-and-forget cleanup of temp images
  FileHelper.cleanupTempImages();

  // Initialize ErrorReportingManager (Bugsnag only on platforms where native plugin exists)
  await ErrorReportingManager.initialize(
    enableBugsnag: !kIsWeb,
  );

  // Set up Flutter error handler with filtering
  FlutterError.onError = (errorDetails) {
    // Filter out non-fatal image decoding errors
    // These are handled by Image.errorBuilder widgets
    final errorString = errorDetails.exception.toString().toLowerCase();
    if (errorString.contains('image decoding') ||
        errorString
            .contains('failed to submit image decoding command buffer') ||
        errorString.contains('codec failed to produce an image') ||
        errorString.contains('failed to load network image')) {
      // Log to console in debug mode but don't report to Bugsnag
      if (kDebugMode) {
        AppLogger.debug(
            'Image loading error (non-fatal, handled by UI): ${errorDetails.exception}');
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
        errorString
            .contains('failed to submit image decoding command buffer') ||
        errorString.contains('codec failed to produce an image') ||
        errorString.contains('failed to load network image')) {
      // Log to console in debug mode but don't report to Bugsnag
      if (kDebugMode) {
        AppLogger.debug(
            'Image loading error (non-fatal, handled by UI): $error');
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

  final navigatorKey = GlobalKey<NavigatorState>();
  if (kDebugMode) {
    AliceInspector.initialize(navigatorKey);
  }

  runApp(PhotoBoothApp(navigatorKey: navigatorKey));
}

class PhotoBoothApp extends StatefulWidget {
  const PhotoBoothApp({super.key, required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<PhotoBoothApp> createState() => _PhotoBoothAppState();
}

class _PhotoBoothAppState extends State<PhotoBoothApp>
    with WidgetsBindingObserver {
  final AppSettingsManager _appSettingsManager = AppSettingsManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appSettingsManager.fetchSettings(forceRefresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appSettingsManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appSettingsManager.fetchSettings(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ChangeNotifierProvider<AppSettingsManager>.value(
          value: _appSettingsManager,
        ),
        Provider<Alice?>.value(value: AliceInspector.instance),
      ],
      child: MaterialApp(
        navigatorKey: widget.navigatorKey,
        title: 'Photo Booth',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, brightness: Brightness.light),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        initialRoute: AppConstants.kRouteTerms,
        routes: {
          AppConstants.kRouteSlideshow: (context) =>
              const ThemeSlideshowScreen(),
          AppConstants.kRouteTerms: (context) =>
              const TermsAndConditionsScreen(),
          AppConstants.kRouteHome: (context) => const ThemeSelectionScreen(),
          AppConstants.kRouteCapture: (context) => const PhotoCaptureScreen(),
          AppConstants.kRouteGenerate: (context) => const PhotoGenerateScreen(),
          AppConstants.kRouteReview: (context) => const PhotoReviewScreen(),
          AppConstants.kRouteResult: (context) => const ResultScreen(),
        },
      ),
    );
  }
}
