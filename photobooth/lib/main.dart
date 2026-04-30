import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'package:flutter_alice/alice.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'screens/theme_slideshow/theme_slideshow_view.dart';
import 'screens/splash/app_splash_screen.dart';
import 'screens/splash/bootstrap_route_args.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/webview/webview_screen.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_generate/photo_generate_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/result/result_view.dart';
import 'screens/qr_share/qr_share_view.dart';
import 'screens/thank_you/thank_you_view.dart';
import 'screens/staff/staff_login_view.dart';
import 'screens/staff/staff_payments_view.dart';
import 'utils/app_runtime_config.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';
import 'services/error_reporting/error_reporting_manager.dart';
import 'services/file_helper.dart';
import 'services/alice_inspector.dart';
import 'services/app_settings_manager.dart';
import 'firebase_options.dart';
import 'services/fcm_token_store.dart';
import 'services/firebase_messaging_background.dart';
import 'services/payment_push_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Generous defaults until `/api/settings` loads; [AppSettingsManager] reapplies limits.
  applyFlutterImageCacheLimits();

  if (DefaultFirebaseOptions.isFirebaseConfigured) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
    }
  }

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
    if (AppConstants.kEnableLogOutput) {
      AppLogger.debug('✅ Error reporting initialized successfully');
      AppLogger.debug(
          'Active services: ${ErrorReportingManager.serviceCount} (Bugsnag: enabled)');
    }
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  AliceInspector.initialize(navigatorKey);

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

  /// Foreground FCM subscription (payment + any future topics).
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedAppSub;
  StreamSubscription<String>? _fcmTokenRefreshSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PaymentPushCoordinator.instance.attachNavigator(widget.navigatorKey);
    _appSettingsManager.fetchSettings(forceRefresh: true);
    if (!kIsWeb && DefaultFirebaseOptions.isFirebaseConfigured) {
      unawaited(_setupPaymentFcmListeners());
    }
  }

  Future<void> _setupPaymentFcmListeners() async {
    // Register streams before any await so a push is never dropped while we
    // wait for permission/token (narrow race on slow devices).
    _fcmOpenedAppSub?.cancel();
    _fcmForegroundSub?.cancel();

    _fcmOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) {
        if (kDebugMode) {
          AppLogger.debug(
            'FCM onMessageOpenedApp (background/killed: user likely tapped notification)',
          );
        }
        PaymentPushCoordinator.instance.handleRemoteMessage(message);
      },
      onError: (e, st) {
        if (kDebugMode) {
          AppLogger.debug('FCM onMessageOpenedApp error: $e');
        }
      },
    );

    _fcmForegroundSub = FirebaseMessaging.onMessage.listen(
      (message) {
        if (kDebugMode) {
          AppLogger.debug(
            'FCM onMessage FOREGROUND (push reached Dart): '
            'data=${message.data} title=${message.notification?.title}',
          );
        }
        PaymentPushCoordinator.instance.handleRemoteMessage(message);
      },
      onError: (e, st) {
        if (kDebugMode) {
          AppLogger.debug('FCM onMessage error: $e');
        }
      },
    );

    _fcmTokenRefreshSub?.cancel();
    _fcmTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        unawaited(FcmTokenStore.save(token));
        if (kDebugMode) {
          AppLogger.debug(
            'FCM token refreshed; persisted locally. Use this token on the next '
            'POST /api/payment/initiate (or backend token-update if you add one): $token',
          );
        }
      },
    );

    if (kDebugMode) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        AppLogger.debug(
          'FCM Firebase project (server Admin SDK must match): '
          '${DefaultFirebaseOptions.android.projectId}',
        );
        AppLogger.debug(
          'FCM Android appId: ${DefaultFirebaseOptions.android.appId}',
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        AppLogger.debug(
          'FCM Firebase project (server Admin SDK must match): '
          '${DefaultFirebaseOptions.ios.projectId}',
        );
      }
      AppLogger.debug(
        'FCM: listeners registered. If you never see "FCM rx message" after paying, '
        'the message is not reaching the device (wrong Firebase project, token not stored server-side, '
        'or not sent). Android: notification-led pushes skip onMessage while backgrounded unless user '
        'taps the notification; use data + android.priority=high for silent wake.',
      );
    }

    final perm = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (kDebugMode) {
      AppLogger.debug('FCM permission: ${perm.authorizationStatus}');
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await FcmTokenStore.save(token);
      }
      if (kDebugMode) {
        if (token != null) {
          AppLogger.debug('FCM registration token (use in payment init & server): $token');
        } else {
          AppLogger.debug('FCM registration token: null');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.debug('FCM getToken failed: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (kDebugMode) {
      AppLogger.debug(
        'FCM getInitialMessage: ${initial != null ? "message present (cold start from notif)" : "null"}',
      );
    }
    if (initial != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PaymentPushCoordinator.instance.handleRemoteMessage(initial);
      });
    }

    if (mounted) {
      await PaymentPushCoordinator.instance.flushPendingStoragePayment();
    }
  }

  @override
  void dispose() {
    _fcmForegroundSub?.cancel();
    _fcmOpenedAppSub?.cancel();
    _fcmTokenRefreshSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _appSettingsManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appSettingsManager.fetchSettings(forceRefresh: true);
      if (!kIsWeb && DefaultFirebaseOptions.isFirebaseConfigured) {
        unawaited(
          PaymentPushCoordinator.instance.flushPendingStoragePayment(),
        );
      }
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
      ],
      child: Consumer<AppSettingsManager>(
        builder: (context, _, __) {
          AliceInspector.syncWithRuntimeConfig();
          return MultiProvider(
            providers: [
              Provider<Alice?>.value(value: AliceInspector.instance),
            ],
            child: MaterialApp(
        navigatorKey: widget.navigatorKey,
        title: AppConstants.kBrandName,
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
        initialRoute: AppConstants.kRouteSplash,
        routes: {
          AppConstants.kRouteSlideshow: (context) =>
              const ThemeSlideshowScreen(),
          AppConstants.kRouteSplash: (context) {
            final raw = ModalRoute.of(context)?.settings.arguments;
            final args = raw is SplashRouteArgs
                ? raw
                : const SplashRouteArgs();
            return AppSplashScreen(args: args);
          },
          AppConstants.kRouteTerms: (context) {
            final raw = ModalRoute.of(context)?.settings.arguments;
            final urls =
                raw is TermsRouteArgs ? raw.backgroundImageUrls : null;
            final bg = (urls != null && urls.isNotEmpty) ? urls : null;
            return TermsAndConditionsScreen(backgroundImageUrls: bg);
          },
          AppConstants.kRouteHome: (context) => const ThemeSelectionScreen(),
          AppConstants.kRouteCapture: (context) => const PhotoCaptureScreen(),
          AppConstants.kRouteGenerate: (context) => const PhotoGenerateScreen(),
          AppConstants.kRouteReview: (context) => const PhotoReviewScreen(),
          AppConstants.kRouteResult: (context) => const ResultScreen(),
          AppConstants.kRouteQrShare: (context) => const QrShareScreen(),
          AppConstants.kRouteThankYou: (context) => const ThankYouScreen(),
          AppConstants.kRouteStaffLogin: (context) => const StaffLoginScreen(),
          AppConstants.kRouteStaffPayments: (context) =>
              const StaffPaymentsScreen(),
          AppConstants.kRouteWebView: (context) => WebViewScreen.fromRouteSettings(
                ModalRoute.of(context)?.settings,
              ),
        },
            ),
          );
        },
      ),
    );
  }
}
