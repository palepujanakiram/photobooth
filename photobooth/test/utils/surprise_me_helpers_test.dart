import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/screens/fotoflashback/surprise_me_upsell_view.dart';
import 'package:photobooth/utils/surprise_me_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';

Map<String, dynamic> _sessionJson(String id) => {
      'id': id,
      'sessionId': id,
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.now().toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    KioskManager.resetPaymentOverrideCacheForTests();
    SessionManager().clearSession();
  });

  tearDown(() {
    SessionManager().clearSession();
  });

  group('surpriseImageFromStatus', () {
    test('returns null when showUpsell is false', () {
      const status = SurpriseMeStatus(
        status: 'ready',
        showUpsell: false,
        imageUrl: 'https://example.com/a.jpg',
      );
      expect(surpriseImageFromStatus(status), isNull);
    });

    test('returns null when image url missing', () {
      const status = SurpriseMeStatus(
        status: 'ready',
        showUpsell: true,
      );
      expect(surpriseImageFromStatus(status), isNull);
    });

    test('builds AI image with portrait print size', () {
      const status = SurpriseMeStatus(
        status: 'ready',
        showUpsell: true,
        imageUrl: 'https://example.com/a.jpg',
        themeId: 'theme-1',
        themeName: 'Neon Night',
      );
      final image = surpriseImageFromStatus(status)!;
      expect(image.imageUrl, 'https://example.com/a.jpg');
      expect(image.theme.name, 'Neon Night');
      expect(image.printSize, AppConstants.kPrintSizePortrait4x6);
      expect(image.isSelected, isTrue);
    });

    test('falls back to Surprise Me title when theme name empty', () {
      const status = SurpriseMeStatus(
        status: 'ready',
        showUpsell: true,
        imageUrl: 'https://example.com/a.jpg',
      );
      final image = surpriseImageFromStatus(status)!;
      expect(image.theme.name, AppStrings.surpriseMeUpsellTitle);
    });
  });

  group('SurpriseMeStatus.fromJson', () {
    test('parses showUpsell gate fields', () {
      final status = SurpriseMeStatus.fromJson({
        'status': 'ready',
        'showUpsell': true,
        'imageUrl': 'https://x/y.jpg',
        'qualityScore': 72,
        'qualityThreshold': 65,
        'themeId': 't1',
        'themeName': 'Noir',
      });
      expect(status.showUpsell, isTrue);
      expect(status.qualityScore, 72);
      expect(status.qualityThreshold, 65);
      expect(status.themeName, 'Noir');
    });
  });

  group('maybeKickoffSurpriseMeAfterShot1', () {
    test('no-ops when flag off', () async {
      final api = FakeApiService();
      await maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,abc',
        enableSurpriseMeAi: false,
        apiService: api,
      );
      expect(api.startSurpriseMeCalls, 0);
    });

    test('no-ops when payments disabled', () async {
      await KioskManager().setPaymentEnabledOverride(false);
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService();
      await maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,abc',
        enableSurpriseMeAi: true,
        apiService: api,
      );
      expect(api.startSurpriseMeCalls, 0);
    });

    test('no-ops without session', () async {
      final api = FakeApiService();
      await maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,abc',
        enableSurpriseMeAi: true,
        apiService: api,
      );
      expect(api.startSurpriseMeCalls, 0);
    });

    test('starts when gated and session present', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService();
      await maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,abc',
        enableSurpriseMeAi: true,
        apiService: api,
      );
      expect(api.startSurpriseMeCalls, 1);
    });

    test('fail-open on API error', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()..startSurpriseMeThrows = true;
      await maybeKickoffSurpriseMeAfterShot1(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,abc',
        enableSurpriseMeAi: true,
        apiService: api,
      );
      expect(api.startSurpriseMeCalls, 1);
    });
  });

  group('fetchSurpriseMeIfReady', () {
    test('returns null without session', () async {
      final api = FakeApiService();
      expect(await fetchSurpriseMeIfReady(apiService: api), isNull);
    });

    test('returns status when session present', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()
        ..surpriseMeStatus = const SurpriseMeStatus(
          status: 'ready',
          showUpsell: true,
          imageUrl: 'https://example.com/a.jpg',
        );
      final status = await fetchSurpriseMeIfReady(apiService: api);
      expect(status?.showUpsell, isTrue);
      expect(api.fetchSurpriseMeStatusCalls, 1);
    });

    test('fail-open on API error', () async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()..fetchSurpriseMeStatusThrows = true;
      expect(await fetchSurpriseMeIfReady(apiService: api), isNull);
    });
  });

  group('maybeOfferSurpriseMeCopy', () {
    testWidgets('returns null when flag off', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));
      final result = await maybeOfferSurpriseMeCopy(
        context: ctx,
        enableSurpriseMeAi: false,
        additionalPrintPrice: 50,
        apiService: FakeApiService(),
      );
      expect(result, isNull);
    });

    testWidgets('returns null when not ready to show', (tester) async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));
      final api = FakeApiService()
        ..surpriseMeStatus = const SurpriseMeStatus(
          status: 'pending',
          showUpsell: false,
        );
      final result = await maybeOfferSurpriseMeCopy(
        context: ctx,
        enableSurpriseMeAi: true,
        additionalPrintPrice: 50,
        apiService: api,
      );
      expect(result, isNull);
    });

    testWidgets('accept returns AI image', (tester) async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()
        ..surpriseMeStatus = const SurpriseMeStatus(
          status: 'ready',
          showUpsell: true,
          imageUrl: 'https://example.com/a.jpg',
          themeName: 'Noir',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final image = await maybeOfferSurpriseMeCopy(
                    context: context,
                    enableSurpriseMeAi: true,
                    additionalPrintPrice: 75,
                    apiService: api,
                  );
                  Navigator.of(context).pop(image?.image?.theme.name);
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.surpriseMeUpsellYes), findsOneWidget);
      await tester.tap(find.text(AppStrings.surpriseMeUpsellYes));
      await tester.pumpAndSettle();
      expect(api.declineSurpriseMeCalls, 0);
    });

    testWidgets('decline calls API', (tester) async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()
        ..surpriseMeStatus = const SurpriseMeStatus(
          status: 'ready',
          showUpsell: true,
          imageUrl: 'https://example.com/a.jpg',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await maybeOfferSurpriseMeCopy(
                    context: context,
                    enableSurpriseMeAi: true,
                    additionalPrintPrice: 50,
                    apiService: api,
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
      await tester.tap(find.text(AppStrings.surpriseMeUpsellNo));
      await tester.pumpAndSettle();
      expect(api.declineSurpriseMeCalls, 1);
    });

    testWidgets('exploreMore returns AI image', (tester) async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      final api = FakeApiService()
        ..surpriseMeStatus = const SurpriseMeStatus(
          status: 'ready',
          showUpsell: true,
          imageUrl: 'https://example.com/a.jpg',
          themeName: 'Noir',
        );
      SurpriseMeOfferResult? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  captured = await maybeOfferSurpriseMeCopy(
                    context: context,
                    enableSurpriseMeAi: true,
                    additionalPrintPrice: 75,
                    apiService: api,
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
      await tester.tap(find.text(AppStrings.surpriseMeUpsellExploreMore));
      await tester.pumpAndSettle();
      expect(captured?.choice, SurpriseMeUpsellChoice.exploreMore);
      expect(captured?.image?.theme.name, 'Noir');
    });

    testWidgets('fail-open when Navigator is unavailable', (tester) async {
      SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      );
      final result = await maybeOfferSurpriseMeCopy(
        context: ctx,
        enableSurpriseMeAi: true,
        additionalPrintPrice: 50,
        apiService: FakeApiService()
          ..surpriseMeStatus = const SurpriseMeStatus(
            status: 'ready',
            showUpsell: true,
            imageUrl: 'https://example.com/a.jpg',
          ),
      );
      expect(result, isNull);
    });
  });
}
