import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/fotoflashback/surprise_me_upsell_view.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/services/print_selection_coordinator.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/fotoflashback_payment_helpers.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/utils/route_args.dart';
import 'package:photobooth/utils/surprise_me_helpers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';
import '../fixtures/theme_fixtures.dart';

class _SeededAppSettingsManager extends AppSettingsManager {
  _SeededAppSettingsManager({AppSettingsModel? settings})
      : _seed = settings ??
            AppSettingsModel(
              parallelImageCount: 1,
              initialPrice: AppConstants.kDefaultInitialPrintPrice,
              paymentGatewayEnabled: true,
            ),
        super(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        );

  final AppSettingsModel _seed;

  @override
  AppSettingsModel? get settings => _seed;

  @override
  bool get hasSettings => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    KioskManager.resetPaymentOverrideCacheForTests();
    SessionManager().clearSession();
    PrintSelectionCoordinator.instance.clear();
  });

  tearDown(() {
    SessionManager().clearSession();
    PrintSelectionCoordinator.instance.clear();
  });

  testWidgets('continueAfterFlashbackLook routes to pre-payment when configured',
      (tester) async {
    await KioskManager().setPaymentEnabledOverride(true);
    SessionManager().setSessionFromResponse(_sessionJson('sess-pre'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _PaymentFlowStripApi(enableOsdScrub: false),
    );
    await vm.loadFilters();
    Object? capturedArgs;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => AppSettingsManager(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await continueAfterFlashbackLook(
                    context: context,
                    viewModel: vm,
                    paymentCollectionTiming:
                        AppConstants.kPaymentCollectionBeforeGeneration,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
          routes: {
            AppConstants.kRoutePrePayment: (context) {
              capturedArgs = ModalRoute.of(context)?.settings.arguments;
              return const SizedBox(key: Key('prepay'));
            },
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prepay')), findsOneWidget);
    expect(capturedArgs, isA<FlashbackPrePayArgs>());
  });

  testWidgets('continueAfterFlashbackLook composes then opens print selection',
      (tester) async {
    await KioskManager().setPaymentEnabledOverride(false);
    SessionManager().setSessionFromResponse(_sessionJson('sess-compose'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _PaymentFlowStripApi(enableOsdScrub: false),
    );
    await vm.loadFilters();
    Object? capturedArgs;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => AppSettingsManager(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await continueAfterFlashbackLook(
                    context: context,
                    viewModel: vm,
                    paymentCollectionTiming:
                        AppConstants.kPaymentCollectionAfterGeneration,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
          routes: {
            AppConstants.kRoutePrintSelection: (context) {
              capturedArgs = ModalRoute.of(context)?.settings.arguments;
              return const SizedBox(key: Key('print-select'));
            },
            AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
            AppConstants.kRouteTerms: (_) => const SizedBox(),
            AppConstants.kRouteHome: (_) => const SizedBox(),
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('print-select')), findsOneWidget);
    final args = capturedArgs as PrintSelectionArgs;
    expect(args.generatedImages, hasLength(1));
    expect(args.generatedImages.first.isSelected, isTrue);
  });

  testWidgets('composeFlashbackAfterPrePay uses default view model when omitted',
      (tester) async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-default-vm'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final args = FlashbackPrePayArgs(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      filterId: kDefaultStripFilterId,
    );
    String? message;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => _SeededAppSettingsManager(),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  message = await composeFlashbackAfterPrePay(
                    context: context,
                    args: args,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(message, isNotNull);
  });

  testWidgets('composeFlashbackAfterPrePay returns compose error message', (tester) async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-compose-err'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final args = FlashbackPrePayArgs(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      filterId: kDefaultStripFilterId,
    );
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: args.imageDataUrls,
      apiService: _PaymentFlowStripApi(failCompose: true),
    );
    String? message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                message = await composeFlashbackAfterPrePay(
                  context: context,
                  args: args,
                  viewModel: vm,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(message, 'compose down');
  });

  testWidgets('continueAfterFlashbackLook reads surprise settings flag', (tester) async {
    await KioskManager().setPaymentEnabledOverride(false);
    SessionManager().setSessionFromResponse(_sessionJson('sess-surprise-flag'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _PaymentFlowStripApi(enableOsdScrub: false),
    );
    await vm.loadFilters();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => _SeededAppSettingsManager(
          settings: AppSettingsModel(enableSurpriseMeAi: true),
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await continueAfterFlashbackLook(
                    context: context,
                    viewModel: vm,
                    paymentCollectionTiming:
                        AppConstants.kPaymentCollectionAfterGeneration,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
          routes: {
            AppConstants.kRoutePrintSelection: (_) => const SizedBox(),
            AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
            AppConstants.kRouteTerms: (_) => const SizedBox(),
            AppConstants.kRouteHome: (_) => const SizedBox(),
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  });

  testWidgets('navigateToFlashbackPrintSelection uses explicit print size fallback',
      (tester) async {
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final strip = GeneratedImage(
      id: 'strip',
      imageUrl: 'https://example.com/strip.jpg',
      theme: theme,
    );
    Object? capturedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFlashbackPrintSelection(
                  context: context,
                  image: strip,
                  printSize: AppConstants.kPrintSizePortrait4x6,
                );
              },
              child: const Text('go'),
            );
          },
        ),
        routes: {
          AppConstants.kRoutePrintSelection: (context) {
            capturedArgs = ModalRoute.of(context)?.settings.arguments;
            return const SizedBox();
          },
          AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
          AppConstants.kRouteTerms: (_) => const SizedBox(),
          AppConstants.kRouteHome: (_) => const SizedBox(),
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final args = capturedArgs as PrintSelectionArgs;
    expect(args.stripPrintSize, AppConstants.kPrintSizePortrait4x6);
    expect(args.canEditLook, isTrue);
  });

  testWidgets('composeFlashbackAfterPrePay composes and navigates', (tester) async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-post-pay'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final args = FlashbackPrePayArgs(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      filterId: kDefaultStripFilterId,
    );
    Object? capturedArgs;
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: args.imageDataUrls,
      apiService: _PaymentFlowStripApi(enableOsdScrub: false),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsManager>(
        create: (_) => AppSettingsManager(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await composeFlashbackAfterPrePay(
                    context: context,
                    args: args,
                    viewModel: vm,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
          routes: {
            AppConstants.kRoutePrintSelection: (context) {
              capturedArgs = ModalRoute.of(context)?.settings.arguments;
              return const SizedBox();
            },
            AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
            AppConstants.kRouteTerms: (_) => const SizedBox(),
            AppConstants.kRouteHome: (_) => const SizedBox(),
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(capturedArgs, isA<PrintSelectionArgs>());
  });

  testWidgets('navigateToFlashbackPrintSelection marks explore more', (tester) async {
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final strip = GeneratedImage(
      id: 'strip',
      imageUrl: 'https://example.com/strip.jpg',
      theme: theme,
      printSize: AppConstants.kPrintSizeStripDual2x6,
    );
    final surprise = GeneratedImage(
      id: 'ai',
      imageUrl: 'https://example.com/ai.jpg',
      theme: sampleTheme('ai'),
      printSize: AppConstants.kPrintSizePortrait4x6,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFlashbackPrintSelection(
                  context: context,
                  image: strip,
                  surpriseOffer: SurpriseMeOfferResult(
                    choice: SurpriseMeUpsellChoice.exploreMore,
                    image: surprise,
                  ),
                  printSize: AppConstants.kPrintSizeStripDual2x6,
                  transformationRunId: 'run-1',
                );
              },
              child: const Text('go'),
            );
          },
        ),
        routes: {
          AppConstants.kRoutePrintSelection: (_) => const SizedBox(),
          AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
          AppConstants.kRouteTerms: (_) => const SizedBox(),
          AppConstants.kRouteHome: (_) => const SizedBox(),
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(PrintSelectionCoordinator.instance.awaitingExploreMoreReturn, isTrue);
  });

  testWidgets('continueAfterFlashbackLook returns compose failure without session',
      (tester) async {
    await KioskManager().setPaymentEnabledOverride(false);
    SessionManager().clearSession();
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _PaymentFlowStripApi(enableOsdScrub: false),
    );
    String? message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                message = await continueAfterFlashbackLook(
                  context: context,
                  viewModel: vm,
                  paymentCollectionTiming:
                      AppConstants.kPaymentCollectionAfterGeneration,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(message, AppStrings.sessionPhotoSyncNoSession);
  });

  testWidgets('continueAfterFlashbackLook returns compose error message', (tester) async {
    await KioskManager().setPaymentEnabledOverride(false);
    SessionManager().setSessionFromResponse(_sessionJson('sess-fail'));
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final vm = FotoFlashbackFilterViewModel(
      theme: theme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _PaymentFlowStripApi(failCompose: true),
    );
    String? message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                message = await continueAfterFlashbackLook(
                  context: context,
                  viewModel: vm,
                  paymentCollectionTiming:
                      AppConstants.kPaymentCollectionAfterGeneration,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(message, 'compose down');
  });

  testWidgets('navigateToFlashbackPrintSelection falls back to default print size',
      (tester) async {
    final theme = sampleTheme('strip').copyWith((p) => p.tier = 'photo_strip');
    final strip = GeneratedImage(
      id: 'strip',
      imageUrl: 'https://example.com/strip.jpg',
      theme: theme,
    );
    Object? capturedArgs;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigateToFlashbackPrintSelection(
                  context: context,
                  image: strip,
                  printSize: '  ',
                  transformationRunId: '  ',
                );
              },
              child: const Text('go'),
            );
          },
        ),
        routes: {
          AppConstants.kRoutePrintSelection: (context) {
            capturedArgs = ModalRoute.of(context)?.settings.arguments;
            return const SizedBox();
          },
          AppConstants.kRouteExperienceChoice: (_) => const SizedBox(),
          AppConstants.kRouteTerms: (_) => const SizedBox(),
          AppConstants.kRouteHome: (_) => const SizedBox(),
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final args = capturedArgs as PrintSelectionArgs;
    expect(args.stripPrintSize, AppConstants.kPrintSizeStripDual2x6);
    expect(args.transformationRunId, isNull);
  });
}

Map<String, dynamic> _sessionJson(String id) => {
      'id': id,
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 31).toIso8601String(),
    };

class _PaymentFlowStripApi extends FakeApiService {
  _PaymentFlowStripApi({this.enableOsdScrub = true, this.failCompose = false});

  final bool enableOsdScrub;
  final bool failCompose;

  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
    return StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'features': {'enableOsdScrub': enableOsdScrub},
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'none',
        },
      ],
    });
  }

  @override
  Future<StripComposeResult> composeStrip({
    required String sessionId,
    required List<String> images,
    String filter = kDefaultStripFilterId,
    String frame = kDefaultStripFrameId,
    String sticker = kDefaultStripStickerId,
    List<StripStickerPlacement> stickerPlacements = const [],
    List<StripScribbleStroke> scribbles = const [],
    bool cleanOverlays = false,
    PrintOrientation? orientation,
    Duration? timeout,
  }) async {
    if (failCompose) {
      throw ApiException('compose down');
    }
    return StripComposeResult(
      imageUrl: 'https://example.com/strip.jpg',
      filter: filter,
      frame: frame,
      sticker: sticker,
      runId: 'run-flow-1',
    );
  }
}
