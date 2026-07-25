import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/experience_choice/experience_choice_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/services/theme_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_api_service.dart';
import '../../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final strip = sampleTheme('strip').copyWith((p) {
    p.tier = 'photo_strip';
    p.name = 'FotoFlashback';
  });
  final ai = sampleTheme('ai');

  Map<String, dynamic> sessionJson(String id) => {
        'id': id,
        'termsAccepted': true,
        'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'attemptsUsed': 0,
        'generatedImages': <dynamic>[],
        'expiresAt': DateTime.utc(2026, 12, 31).toIso8601String(),
      };

  test('load detects FotoFlashback availability', () async {
    final api = _ThemesFakeApi(themes: [ai, strip]);
    final vm = ExperienceChoiceViewModel(
      themeManager: ThemeManager.forTesting(api),
      apiService: api,
    );
    await vm.load();
    expect(vm.fotoFlashAvailable, isTrue);
    expect(vm.fotoFlashTheme?.id, 'strip');
  });

  test('prepareFotoFlashback updates session theme', () async {
    final api = _ThemesFakeApi(
      themes: [strip],
      sessionResponse: sessionJson('sess-ff'),
    );
    SessionManager().setSessionFromResponse(sessionJson('sess-ff'));
    final vm = ExperienceChoiceViewModel(
      themeManager: ThemeManager.forTesting(api),
      apiService: api,
    );
    await vm.load();
    final theme = await vm.prepareFotoFlashback();
    expect(theme?.id, 'strip');
    expect(api.lastSelectedThemeId, 'strip');
  });

  test('prepareFotoFlashback fails when strip theme missing', () async {
    final api = _ThemesFakeApi(themes: [ai]);
    SessionManager().setSessionFromResponse(sessionJson('sess-1'));
    final vm = ExperienceChoiceViewModel(
      themeManager: ThemeManager.forTesting(api),
      apiService: api,
    );
    await vm.load();
    expect(await vm.prepareFotoFlashback(), isNull);
    expect(vm.errorMessage, isNotNull);
  });

  test('prepareFotoFlashback surfaces API errors', () async {
    final api = _ThemesFakeApi(themes: [strip], patchThrows: true);
    SessionManager().setSessionFromResponse(sessionJson('sess-1'));
    final vm = ExperienceChoiceViewModel(
      themeManager: ThemeManager.forTesting(api),
      apiService: api,
    );
    await vm.load();
    expect(await vm.prepareFotoFlashback(), isNull);
    expect(vm.errorMessage, 'patch failed');
  });
}

class _ThemesFakeApi extends FakeApiService {
  _ThemesFakeApi({
    required this.themes,
    super.patchThrows,
    super.sessionResponse,
  });

  final List<ThemeModel> themes;
  String? lastSelectedThemeId;

  @override
  Future<List<ThemeModel>> getThemes() async => themes;

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
    lastSelectedThemeId = selectedThemeId;
    if (patchThrows) throw ApiException('patch failed');
    return sessionResponse;
  }
}
