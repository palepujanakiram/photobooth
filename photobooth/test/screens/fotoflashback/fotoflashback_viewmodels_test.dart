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
    expect(vm.frames, hasLength(2));
    expect(vm.stickers, hasLength(2));
    expect(vm.selectedFilter?.id, kDefaultStripFilterId);
    expect(vm.selectedFrameId, kDefaultStripFrameId);
    expect(vm.selectedStickerId, kDefaultStripStickerId);
    vm.selectFrame('noir');
    vm.selectSticker('hearts');
    expect(vm.selectedFrameId, 'noir');
    expect(vm.selectedStickerId, 'hearts');
    // One heart per photo cell.
    expect(vm.stickerPlacements, hasLength(kStripShotCount));
    expect(
      vm.stickerPlacements.map((p) => p.y).toSet(),
      hasLength(kStripShotCount),
    );
    vm.moveSticker(vm.stickerPlacements.first.id, 0.4, 0.5);
    expect(vm.stickerPlacements.first.x, 0.4);
    expect(vm.stickerPlacements.first.y, 0.5);
    vm.selectFilter('mono');
    expect(vm.selectedFilterId, 'mono');
    expect(vm.selectedFilter?.id, 'mono');
    vm.selectFilter('mono');
    expect(vm.selectedFilterId, 'mono');

    // Overlay polish disabled (DSLR MF) — shots stay as-captured.
    await vm.preparePreview();
    expect(vm.previewCleaned, isFalse);
    expect(vm.imageDataUrls.every((u) => u.endsWith('_clean')), isFalse);

    final image = await vm.compose();
    expect(image, isNotNull);
    expect(image!.imageUrl, 'https://example.com/strip.jpg');
    expect(image.isSelected, isTrue);
    expect(vm.composeResult, isNotNull);
    expect(api.composeCalls, 1);
    expect(api.lastCleanOverlays, isFalse);
    expect(api.lastFrame, 'noir');
    expect(api.lastSticker, kDefaultStripStickerId);
    expect(api.lastPlacements, hasLength(kStripShotCount));
  });

  test('FotoFlashbackFilterViewModel scribble draw/undo/clear', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
    );
    vm.setDrawMode(true);
    expect(vm.drawMode, isTrue);
    vm.setPenColor('#FF4D6D');
    expect(vm.penColor, '#FF4D6D');
    vm.beginScribble(0.2, 0.2);
    vm.extendScribble(0.3, 0.25);
    vm.extendScribble(0.4, 0.3);
    vm.endScribble();
    expect(vm.scribbles, hasLength(1));
    expect(vm.scribbles.first.points, hasLength(3));
    vm.undoScribble();
    expect(vm.scribbles, isEmpty);
    vm.beginScribble(0.1, 0.1);
    vm.extendScribble(0.2, 0.2);
    vm.endScribble();
    vm.clearScribbles();
    expect(vm.scribbles, isEmpty);
    expect(vm.canUndoScribble, isFalse);
  });

  test('FotoFlashbackFilterViewModel sticker add/move/clear', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
    );
    expect(vm.canCompose, isTrue);
    expect(vm.isPreparingPreview, isFalse);
    vm.addSticker('sparkles');
    expect(vm.stickerPlacements, hasLength(kStripShotCount));
    vm.addSticker('confetti');
    expect(vm.stickerPlacements, hasLength(kStripShotCount * 2));
    expect(
      vm.stickerPlacements.where((p) => p.type == 'confetti'),
      hasLength(kStripShotCount),
    );
    final id = vm.stickerPlacements.first.id;
    vm.removeSticker(id);
    expect(vm.stickerPlacements, hasLength(kStripShotCount * 2 - 1));
    vm.clearStickers();
    expect(vm.stickerPlacements, isEmpty);
    expect(vm.selectedStickerId, kDefaultStripStickerId);
    vm.selectSticker('none');
    expect(vm.stickerPlacements, isEmpty);
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

    final altChrome = _StripFakeApi(altChromeOnly: true);
    final resetChrome = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: altChrome,
    );
    await resetChrome.loadFilters();
    expect(resetChrome.selectedFrameId, 'noir');
    expect(resetChrome.selectedStickerId, kDefaultStripStickerId);
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
    this.altChromeOnly = false,
  });

  final bool failCompose;
  final bool failLoad;
  final bool throwGenericLoad;
  final bool throwGenericCompose;
  final bool monoOnly;
  final bool altChromeOnly;
  int composeCalls = 0;

  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
    if (failLoad) throw ApiException('filters down');
    if (throwGenericLoad) throw Exception('load boom');
    if (altChromeOnly) {
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
        ],
        'frames': [
          {'id': 'noir', 'name': 'Noir Matte', 'description': 'Dark'},
        ],
        'stickers': [
          {'id': 'hearts', 'name': 'Hearts', 'description': 'Hearts'},
        ],
      });
    }
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
      'frames': [
        {'id': 'classic', 'name': 'Classic', 'description': 'White'},
        {'id': 'noir', 'name': 'Noir Matte', 'description': 'Dark'},
      ],
      'stickers': [
        {'id': 'none', 'name': 'None', 'description': 'Off'},
        {'id': 'hearts', 'name': 'Hearts', 'description': 'Hearts'},
      ],
    });
  }

  @override
  Future<List<String>> gradeStripPreview({
    required String sessionId,
    required List<String> images,
    String filter = kDefaultStripFilterId,
  }) async {
    return images.map((e) => '${e}_graded_$filter').toList();
  }

  @override
  Future<List<String>> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    return images
        .map((e) => e.endsWith('_clean') ? e : '${e}_clean')
        .toList();
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
  }) async {
    composeCalls++;
    lastCleanOverlays = cleanOverlays;
    lastFrame = frame;
    lastSticker = sticker;
    lastPlacements = List<StripStickerPlacement>.from(stickerPlacements);
    lastScribbles = List<StripScribbleStroke>.from(scribbles);
    if (failCompose) {
      throw ApiException('compose down');
    }
    if (throwGenericCompose) {
      throw Exception('compose boom');
    }
    return StripComposeResult(
      imageUrl: 'https://example.com/strip.jpg',
      filter: filter,
      frame: frame,
      sticker: sticker,
    );
  }

  String? lastFrame;
  String? lastSticker;
  List<StripStickerPlacement>? lastPlacements;
  List<StripScribbleStroke>? lastScribbles;

  bool? lastCleanOverlays;
}
