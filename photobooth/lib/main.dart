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
import 'package:overlay_support/overlay_support.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'app_routes.dart';
import 'main_error_handlers.dart';
import 'utils/app_route_tracker.dart';
import 'utils/app_runtime_config.dart';
import 'utils/constants.dart';
import 'utils/logger.dart';
import 'views/widgets/debug_performance_overlays.dart';
import 'services/error_reporting/error_reporting_manager.dart';
import 'services/file_helper.dart';
import 'services/alice_inspector.dart';
import 'services/app_settings_manager.dart';
import 'firebase_options.dart';
import 'services/fcm_token_store.dart';
import 'services/firebase_messaging_background.dart';
import 'services/payment_push_coordinator.dart';
import 'services/api_service.dart';
import 'services/client_identification.dart';
import 'services/session_manager.dart';
import 'services/low_memory_monitor.dart';
import 'utils/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ClientIdentification.ensureInitialized();

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

  // Bugsnag: release/profile mobile only (debug skips it; key from photobooth/.env at build time).
  final bugsnagActive = !kIsWeb &&
      !kDebugMode &&
      AppConfig.bugsnagApiKey.isNotEmpty;
  if (bugsnagActive) {
    try {
      await bugsnag.start(
        apiKey: AppConfig.bugsnagApiKey,
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
  } else if (!kIsWeb && !kDebugMode && AppConfig.bugsnagApiKey.isEmpty) {
    AppLogger.error(
      'BUGSNAG_API_KEY missing for release/profile build; Bugsnag disabled. '
      'Add BUGSNAG_API_KEY to photobooth/.env and rebuild with scripts/flutter_with_version.sh.',
    );
  }

  // Fire-and-forget cleanup of temp images
  FileHelper.cleanupTempImages();

  // Initialize ErrorReportingManager (Bugsnag only on platforms where native plugin exists)
  await ErrorReportingManager.initialize(
    enableBugsnag: bugsnagActive,
  );

  configureFlutterErrorHandlers();

  await SessionManager().restore();

  logErrorReportingReady();

  if (!kIsWeb) {
    LowMemoryMonitor.instance.start();
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
  final AppRouteTracker _routeTracker = AppRouteTracker();

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

  void _registerPaymentFcmStreams() {
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
        final sessionId = SessionManager().sessionId;
        if (sessionId != null && sessionId.trim().isNotEmpty) {
          unawaited(
            ApiService().registerSessionFcmToken(
              sessionId: sessionId,
              fcmToken: token,
            ),
          );
        }
        if (kDebugMode) {
          AppLogger.debug(
            'FCM token refreshed; persisted locally. Use this token on the next '
            'POST /api/payment/initiate (or backend token-update if you add one): $token',
          );
        }
      },
    );
  }

  void _logFcmSetupHints() {
    if (!kDebugMode) return;
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

  Future<void> _requestFcmPermissionAndPersistToken() async {
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
        AppLogger.debug(
          token != null
              ? 'FCM registration token (use in payment init & server): $token'
              : 'FCM registration token: null',
        );
      }
    } catch (e) {
      if (kDebugMode) AppLogger.debug('FCM getToken failed: $e');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }
  }

  Future<void> _deliverFcmColdStartMessageIfAny() async {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (kDebugMode) {
      AppLogger.debug(
        'FCM getInitialMessage: ${initial != null ? "message present (cold start from notif)" : "null"}',
      );
    }
    if (initial != null) {
      PaymentPushCoordinator.instance.queueRemoteMessage(initial);
    }
  }

  Future<void> _setupPaymentFcmListeners() async {
    _registerPaymentFcmStreams();
    _logFcmSetupHints();
    await _requestFcmPermissionAndPersistToken();
    await _deliverFcmColdStartMessageIfAny();

    if (mounted) {
      await PaymentPushCoordinator.instance.flushPendingStoragePayment();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      LowMemoryMonitor.instance.stop();
    }
    _fcmForegroundSub?.cancel();
    _fcmOpenedAppSub?.cancel();
    _fcmTokenRefreshSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _appSettingsManager.dispose();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    LowMemoryMonitor.instance.onMemoryPressure();
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
        ChangeNotifierProvider<SessionManager>.value(value: SessionManager()),
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ChangeNotifierProvider<AppSettingsManager>.value(
          value: _appSettingsManager,
        ),
        Provider<Alice?>.value(value: AliceInspector.instance),
      ],
      child: OverlaySupport.global(
        child: ListenableBuilder(
          listenable: _routeTracker,
          builder: (context, _) {
            return MaterialApp(
              navigatorKey: widget.navigatorKey,
              navigatorObservers: [_routeTracker],
              title: AppConstants.kBrandName,
              debugShowCheckedModeBanner: false,
              builder: (context, child) {
                return Consumer<AppSettingsManager>(
                  builder: (context, _, __) {
                    AliceInspector.syncWithRuntimeConfig();
                    return DebugPerformanceOverlayScope(
                      routeName: _routeTracker.currentRouteName,
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                );
              },
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
              routes: buildAppRoutes(),
            );
          },
        ),
      ),
    );
  }
}
