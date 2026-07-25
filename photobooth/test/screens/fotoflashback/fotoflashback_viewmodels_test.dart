import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_capture_viewmodel.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_api_service.dart';
import '../../fixtures/theme_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final stripTheme = sampleTheme('strip1').copyWith((p) {
    p.tier = 'photo_strip';
    p.name = 'FotoFlashback';
  });

  test('ThemeModel.isPhotoStrip detects photo_strip tier', () {
    expect(stripTheme.isPhotoStrip, isTrue);
    expect(sampleTheme('ai').isPhotoStrip, isFalse);
    expect(
      sampleTheme('x').copyWith((p) => p.tier = 'PHOTO_STRIP').isPhotoStrip,
      isTrue,
    );
  });

  test('FotoFlashbackFilterViewModel uses production defaults', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
    );
    expect(vm.canCompose, isTrue);
    expect(vm.selectedFilterId, kDefaultStripFilterId);
  });

  test('FotoFlashbackCaptureViewModel collects four shots', () {
    final vm = FotoFlashbackCaptureViewModel(theme: stripTheme);
    expect(vm.isComplete, isFalse);
    expect(vm.nextShotNumber, 1);
    vm.removeLastShot();
    vm.clearShots();
    expect(vm.shotCount, 0);
    for (var i = 0; i < kStripShotCount; i++) {
      expect(vm.nextShotNumber, i + 1);
      vm.addShot(
        PhotoModel(
          id: 's$i',
          imageFile: XFile.fromData(
            Uint8List.fromList([0xFF, 0xD8, 0xFF, i]),
            name: 's$i.jpg',
            mimeType: 'image/jpeg',
          ),
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
    expect(vm.isComplete, isTrue);
    expect(vm.shotCount, kStripShotCount);
    expect(vm.nextShotNumber, kStripShotCount);
    expect(vm.shots, hasLength(kStripShotCount));
    vm.addShot(
      PhotoModel(
        id: 'extra',
        imageFile: XFile.fromData(
          Uint8List.fromList([0xFF, 0xD8, 0xFF]),
          name: 'extra.jpg',
          mimeType: 'image/jpeg',
        ),
        capturedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    expect(vm.shotCount, kStripShotCount);
    vm.removeLastShot();
    expect(vm.shotCount, kStripShotCount - 1);
    vm.clearShots();
    expect(vm.shotCount, 0);
  });

  test('FotoFlashbackFilterViewModel loads filters and composes', () async {
    final api = _StripFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
    );

    expect(vm.canCompose, isTrue);
    expect(vm.filters, isEmpty);
    expect(vm.selectedFilter, isNull);
    await vm.loadFilters();
    expect(vm.filters, hasLength(2));
    expect(vm.selectedFilter?.id, kDefaultStripFilterId);
    vm.selectFilter('mono');
    expect(vm.selectedFilterId, 'mono');
    expect(vm.selectedFilter?.id, 'mono');
    vm.selectFilter('mono');
    expect(vm.selectedFilterId, 'mono');

    final image = await vm.compose();
    expect(image, isNotNull);
    expect(image!.imageUrl, 'https://example.com/strip.jpg');
    expect(image.isSelected, isTrue);
    expect(vm.composeResult, isNotNull);
    expect(api.composeCalls, 1);
  });

  test('FotoFlashbackFilterViewModel surfaces compose errors', () async {
    final api = _StripFakeApi(failCompose: true);
    SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
    );
    final image = await vm.compose();
    expect(image, isNull);
    expect(vm.errorMessage, 'compose down');
  });

  test('FotoFlashbackFilterViewModel handles load/compose edge cases', () async {
    SessionManager().clearSession();
    final shortVm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['a', 'b'],
      apiService: _StripFakeApi(),
    );
    expect(shortVm.canCompose, isFalse);
    expect(await shortVm.compose(), isNull);
    expect(shortVm.errorMessage, isNotNull);

    SessionManager().clearSession();
    final noSession = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
    );
    expect(await noSession.compose(), isNull);
    expect(noSession.errorMessage, isNotNull);

    final apiFail = _StripFakeApi(failLoad: true);
    final loadFail = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: apiFail,
    );
    await loadFail.loadFilters();
    expect(loadFail.errorMessage, 'filters down');

    final apiBoom = _StripFakeApi(throwGenericLoad: true);
    final loadBoom = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: apiBoom,
    );
    await loadBoom.loadFilters();
    expect(loadBoom.errorMessage, contains('load boom'));

    final apiComposeBoom = _StripFakeApi(throwGenericCompose: true);
    SessionManager().setSessionFromResponse(_sessionJson('sess-1'));
    final composeBoom = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: apiComposeBoom,
    );
    expect(await composeBoom.compose(), isNull);
    expect(composeBoom.errorMessage, isNotNull);

    final monoOnly = _StripFakeApi(monoOnly: true);
    final resetDefault = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: monoOnly,
    );
    await resetDefault.loadFilters();
    expect(resetDefault.selectedFilterId, 'mono');
    expect(resetDefault.imageDataUrls, hasLength(4));
    expect(resetDefault.catalog, isNotNull);
    expect(resetDefault.isLoading, isFalse);
    expect(resetDefault.isComposing, isFalse);
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

class _StripFakeApi extends FakeApiService {
  _StripFakeApi({
    this.failCompose = false,
    this.failLoad = false,
    this.throwGenericLoad = false,
    this.throwGenericCompose = false,
    this.monoOnly = false,
  });

  final bool failCompose;
  final bool failLoad;
  final bool throwGenericLoad;
  final bool throwGenericCompose;
  final bool monoOnly;
  int composeCalls = 0;

  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
    if (failLoad) throw ApiException('filters down');
    if (throwGenericLoad) throw Exception('load boom');
    if (monoOnly) {
      return StripFiltersCatalog.fromJson({
        'brand': 'FotoFlashback',
        'shotCount': 4,
        'filters': [
          {
            'id': 'mono',
            'name': 'Noir',
            'description': 'B&W',
            'cssFilter': 'grayscale(1)',
          },
        ],
      });
    }
    return StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'none',
        },
        {
          'id': 'mono',
          'name': 'Noir',
          'description': 'B&W',
          'cssFilter': 'grayscale(1)',
        },
      ],
    });
  }

  @override
  Future<StripComposeResult> composeStrip({
    required String sessionId,
    required List<String> images,
    String filter = kDefaultStripFilterId,
  }) async {
    composeCalls++;
    if (failCompose) {
      throw ApiException('compose down');
    }
    if (throwGenericCompose) {
      throw Exception('compose boom');
    }
    return StripComposeResult(
      imageUrl: 'https://example.com/strip.jpg',
      filter: filter,
    );
  }
}
