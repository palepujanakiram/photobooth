import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/screens/frame_select/frame_select_viewmodel.dart';
import 'package:photobooth/screens/terms_and_conditions/terms_and_conditions_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';
import '../fakes/fake_kiosk_manager.dart';
import '../fixtures/theme_fixtures.dart';

class _PatchApi extends FakeApiService {
  _PatchApi({this.throwPatch = false, this.frames = const []});

  final bool throwPatch;
  final List<KioskFrameModel> frames;

  @override
  Future<Map<String, dynamic>> updateSession({
    required String sessionId,
    String? userImageUrl,
    String? selectedThemeId,
    bool includeSelectedFrameId = false,
    String? selectedFrameId,
    int? personCount,
    Map<String, dynamic>? framingMetadata,
  }) async {
    if (throwPatch) throw ApiException('patch fail');
    return {
      'id': sessionId,
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      if (selectedThemeId != null) 'selectedThemeId': selectedThemeId,
    };
  }

  @override
  Future<List<KioskFrameModel>> getKioskFrames() async => frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionManager().clearSession();
  });

  group('ThemeViewModel', () {
    test('full selection and session update flow', () async {
      final tm = ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')]));
      await tm.fetchThemes();
      final api = _PatchApi();
      final vm = ThemeViewModel(themeManager: tm, apiService: api);
      await vm.loadThemes();
      vm.selectCategory('All');
      vm.setCarouselIndex(0);
      vm.advanceCarousel();
      vm.armTheme(vm.themes.first);
      vm.clearNoThemesMessage();
      vm.updateFromCache();

      SessionManager().setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      });
      expect(await vm.updateSessionWithTheme(), isTrue);

      final frames = await vm.fetchKioskFramesList();
      expect(frames, isEmpty);
      vm.dispose();
    });

    test('sync frame helpers and errors', () async {
      final api = _PatchApi(
        frames: [
          const KioskFrameModel(id: 'f1', name: 'F', overlayUrl: 'https://cdn/o.png'),
        ],
      );
      final vm = ThemeViewModel(
        themeManager: ThemeManager.forTesting(ThemesFakeApi([sampleTheme('t1')])),
        apiService: api,
      );
      SessionManager().setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      });
      expect(await vm.syncSingleFrameSelection('f1'), isTrue);
      expect(await vm.syncAutoSkippedFrameSelection(), isTrue);
      expect(await vm.syncSingleFrameSelection('f1'), isTrue);
      SessionManager().clearSession();
      expect(await vm.syncSingleFrameSelection('f1'), isFalse);
      vm.dispose();
    });

    test('loadThemes empty triggers no themes flag', () async {
      final vm = ThemeViewModel(
        themeManager: ThemeManager.forTesting(ThemesFakeApi([])),
        apiService: FakeApiService(),
      );
      await vm.loadThemes();
      expect(vm.showNoThemesMessage, isTrue);
      vm.clearNoThemesMessage();
      expect(vm.showNoThemesMessage, isFalse);
      vm.dispose();
    });
  });

  group('TermsAndConditionsViewModel', () {
    test('validateAndSetKioskCode with fake kiosk manager', () async {
      final vm = TermsAndConditionsViewModel(
        apiService: FakeApiService(validateKioskCodeResult: true),
        kioskManager: FakeKioskManager(code: 'OLD'),
      );
      expect(await vm.validateAndSetKioskCode('NEW'), isTrue);
    });
  });

  group('FrameSelectViewModel', () {
    test('patchSelectedFrame success', () async {
      SessionManager().setSessionFromResponse({
        'id': 'sess-1',
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': [],
        'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
      });
      final vm = FrameSelectViewModel(
        apiService: _PatchApi(
          frames: [
            const KioskFrameModel(id: 'f1', name: 'F', overlayUrl: 'https://cdn/o.png'),
          ],
        ),
      );
      await vm.loadFrames();
      expect(
        await vm.patchSelectedFrameAndSyncSession(
          includeSelectedFrameId: true,
          selectedFrameId: 'f1',
        ),
        isTrue,
      );
    });
  });
}
