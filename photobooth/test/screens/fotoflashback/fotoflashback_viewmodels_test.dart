import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_capture_viewmodel.dart';
import 'package:photobooth/screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/classic_strip_scrub_coordinator.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/utils/strip_look_color_matrices.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_api_service.dart';
import '../../fixtures/theme_fixtures.dart';
import '../../helpers/tiny_jpeg.dart';

String _tinyJpegDataUrl() {
  final src = img.Image(width: 4, height: 4);
  img.fill(src, color: img.ColorRgb8(20, 40, 60));
  return 'data:image/jpeg;base64,'
      '${base64Encode(img.encodeJpg(src, quality: 90))}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    ClassicStripScrubCoordinator.instance.resetForTests();
    FotoFlashbackFilterViewModel.composeWarmJoinTimeoutForTest =
        const Duration(seconds: 45);
  });

  tearDown(() {
    ClassicStripScrubCoordinator.instance.resetForTests();
    FotoFlashbackFilterViewModel.composeWarmJoinTimeoutForTest =
        const Duration(seconds: 45);
  });

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
    expect(vm.printOrientation, PrintOrientation.portrait);
  });

  test('FotoFlashbackFilterViewModel hydrates pending capture file paths',
      () async {
    final path =
        '${Directory.systemTemp.path}/ptp_hydrate_test_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(kTinyJpegBytes);

    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const [],
      pendingImageFilePaths: [path],
      overlayCleanupBuildGate: false,
    );
    expect(vm.isHydratingCaptures, isTrue);
    expect(vm.isSingleClassic, isTrue);
    expect(vm.canCompose, isFalse);

    for (var i = 0; i < 50 && vm.isHydratingCaptures; i++) {
      await pumpEventQueue();
    }

    expect(vm.isHydratingCaptures, isFalse);
    expect(vm.hasLookPreviewJpegBytes, isTrue);
    expect(vm.lookPreviewJpegBytes, hasLength(1));
    expect(vm.imageDataUrls, hasLength(1));
    expect(vm.imageDataUrls.first, startsWith('data:image/jpeg;base64,'));
    expect(vm.canCompose, isTrue);
  });

  test('FotoFlashbackFilterViewModel hydrate surfaces an empty capture file',
      () async {
    // A direct-PTP path that exists but holds no bytes: the transfer was cut
    // short. Compose would reject it later, so the look screen has to say so.
    final path =
        '${Directory.systemTemp.path}/ptp_hydrate_empty_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(Uint8List(0));

    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const [],
      pendingImageFilePaths: [path],
      overlayCleanupBuildGate: false,
    );

    for (var i = 0; i < 50 && vm.isHydratingCaptures; i++) {
      await pumpEventQueue();
    }

    expect(vm.isHydratingCaptures, isFalse);
    expect(vm.errorMessage, AppStrings.flashbackFinishEncodeFailed);
    expect(vm.hasLookPreviewJpegBytes, isFalse);
    expect(vm.imageDataUrls, isEmpty);
    expect(vm.canCompose, isFalse);
  });

  test('FotoFlashbackFilterViewModel hydrate kicks off overlay scrub after encode',
      () async {
    final path =
        '${Directory.systemTemp.path}/ptp_hydrate_scrub_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(kTinyJpegBytes);
    SessionManager().setSessionFromResponse(_sessionJson('sess-hydrate-scrub'));
    final api = _CountingScrubFakeApi();

    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const [],
      pendingImageFilePaths: [path],
      overlayCleanupBuildGate: true,
      apiService: api,
    );
    await vm.loadFilters();

    for (var i = 0; i < 100 && vm.isHydratingCaptures; i++) {
      await pumpEventQueue();
    }
    expect(vm.isHydratingCaptures, isFalse);
    expect(vm.imageDataUrls, hasLength(1));
  });

  test('FotoFlashbackFilterViewModel hydrate reports encode failure', () async {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const [],
      pendingImageFilePaths: ['/nonexistent/ptp_hydrate_missing.jpg'],
      overlayCleanupBuildGate: false,
    );

    for (var i = 0; i < 50 && vm.isHydratingCaptures; i++) {
      await pumpEventQueue();
    }

    expect(vm.isHydratingCaptures, isFalse);
    expect(vm.errorMessage, AppStrings.flashbackFinishEncodeFailed);
    expect(vm.imageDataUrls, isEmpty);
  });

  test('FotoFlashbackFilterViewModel clearCapturePreview drops stale bytes',
      () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      overlayCleanupBuildGate: false,
    );
    expect(vm.previewImageDataUrls, isNotEmpty);

    vm.clearCapturePreview();

    expect(vm.previewImageDataUrls, isEmpty);
    expect(vm.imageDataUrls, isEmpty);
    expect(vm.canCompose, isFalse);
  });

  test(
      'FotoFlashbackFilterViewModel clearCapturePreview cancels in-flight hydrate',
      () async {
    final dir = await Directory.systemTemp.createTemp('hydrate_cancel_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/shot.jpg';
    await File(path).writeAsBytes(kTinyJpegBytes);

    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const [],
      pendingImageFilePaths: [path],
      overlayCleanupBuildGate: false,
    );
    expect(vm.isHydratingCaptures, isTrue);

    vm.clearCapturePreview();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(vm.previewImageDataUrls, isEmpty);
    expect(vm.isHydratingCaptures, isFalse);
  });

  test('FotoFlashbackFilterViewModel print orientation for 1-shot only', () {
    final single = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: ['data:image/jpeg;base64,/9j/4AAQ'],
    );
    expect(single.printOrientation, PrintOrientation.portrait);
    single.selectPrintOrientation(PrintOrientation.landscape);
    expect(single.printOrientation, PrintOrientation.landscape);
    single.selectPrintOrientation(PrintOrientation.portrait);
    expect(single.printOrientation, PrintOrientation.portrait);

    final four = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
    );
    expect(four.printOrientation, PrintOrientation.portrait);
    four.selectPrintOrientation(PrintOrientation.landscape);
    expect(four.printOrientation, PrintOrientation.portrait);
  });

  test('FotoFlashbackFilterViewModel retries unfinished scrub', () async {
    final api = _FlakyScrubFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-retry-scrub'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      shotCleaned: const [true, true, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await vm.preparePreview();
    expect(vm.hasUnfinishedScrub, isTrue);
    expect(vm.canRetryUnfinishedScrub, isTrue);
    expect(
      vm.scrubDotStatuses.where((s) => s == ClassicScrubDotStatus.failed),
      hasLength(2),
    );

    api.succeedRemaining = true;
    await vm.retryUnfinishedScrub();
    expect(vm.hasUnfinishedScrub, isFalse);
    expect(vm.previewCleaned, isTrue);
    expect(vm.canRetryUnfinishedScrub, isFalse);
  });

  test('FotoFlashbackFilterViewModel adopts in-flight capture scrub', () async {
    ClassicStripScrubCoordinator.instance.resetForTests();
    final scrubApi = _CountingScrubFakeApi();
    final lookApi = _CountingScrubFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-adopt-scrub'));

    final urls = [
      for (var i = 0; i < 4; i++) 'data:image/jpeg;base64,raw$i',
    ];
    for (final url in urls) {
      ClassicStripScrubCoordinator.instance.enqueueShot(
        encodeShotDataUrl: () async => url,
        enableScrub: true,
        apiService: scrubApi,
      );
    }

    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List<String>.from(urls),
      apiService: lookApi,
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await vm.preparePreview();

    expect(lookApi.cleanCalls, 0);
    expect(scrubApi.cleanCalls, 4);
    expect(vm.previewCleaned, isTrue);
    expect(vm.hasUnfinishedScrub, isFalse);
    expect(
      vm.imageDataUrls,
      [
        for (var i = 0; i < 4; i++) 'data:image/jpeg;base64,raw${i}_clean',
      ],
    );
    ClassicStripScrubCoordinator.instance.resetForTests();
  });

  test(
    'FotoFlashbackFilterViewModel re-posts when capture scrub failed',
    () async {
      ClassicStripScrubCoordinator.instance.resetForTests();
      final scrubApi = _FailingScrubFakeApi();
      final lookApi = _CountingScrubFakeApi();
      SessionManager().setSessionFromResponse(
        _sessionJson('sess-fail-adopt-repost'),
      );

      final urls = [
        for (var i = 0; i < 4; i++) 'data:image/jpeg;base64,raw$i',
      ];
      for (final url in urls) {
        ClassicStripScrubCoordinator.instance.enqueueShot(
          encodeShotDataUrl: () async => url,
          enableScrub: true,
          apiService: scrubApi,
        );
      }
      await ClassicStripScrubCoordinator.instance.awaitAll();

      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List<String>.from(urls),
        apiService: lookApi,
        shotCleaned: const [false, false, false, false],
        overlayCleanupBuildGate: true,
      );
      await vm.loadFilters();
      await vm.preparePreview();

      // Failed capture results must not block look-screen re-clean.
      expect(lookApi.cleanCalls, 4);
      expect(vm.previewCleaned, isTrue);
      expect(vm.hasUnfinishedScrub, isFalse);
      ClassicStripScrubCoordinator.instance.resetForTests();
    },
  );

  test(
    'FotoFlashbackFilterViewModel refresh re-scrubs after failed adopt',
    () async {
      ClassicStripScrubCoordinator.instance.resetForTests();
      final scrubApi = _FailingScrubFakeApi();
      final lookApi = _FlakyScrubFakeApi();
      SessionManager().setSessionFromResponse(
        _sessionJson('sess-refresh-failed'),
      );

      final urls = [
        for (var i = 0; i < 4; i++) 'data:image/jpeg;base64,raw$i',
      ];
      for (final url in urls) {
        ClassicStripScrubCoordinator.instance.enqueueShot(
          encodeShotDataUrl: () async => url,
          enableScrub: true,
          apiService: scrubApi,
        );
      }
      await ClassicStripScrubCoordinator.instance.awaitAll();

      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List<String>.from(urls),
        apiService: lookApi,
        shotCleaned: const [false, false, false, false],
        overlayCleanupBuildGate: true,
      );
      await vm.loadFilters();
      await vm.preparePreview();
      expect(vm.hasUnfinishedScrub, isTrue);
      expect(vm.canRetryUnfinishedScrub, isTrue);

      lookApi.succeedRemaining = true;
      await vm.retryUnfinishedScrub();
      expect(vm.hasUnfinishedScrub, isFalse);
      expect(vm.previewCleaned, isTrue);
      ClassicStripScrubCoordinator.instance.resetForTests();
    },
  );

  test('FotoFlashbackFilterViewModel falls back when scrub returns empty',
      () async {
    ClassicStripScrubCoordinator.instance.resetForTests();
    final api = _EmptyScrubFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-empty-scrub'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await vm.preparePreview();
    expect(vm.previewCleaned, isFalse);
    expect(vm.hasUnfinishedScrub, isTrue);
  });

  test('FotoFlashbackFilterViewModel ignores empty coordinator scrub result',
      () async {
    ClassicStripScrubCoordinator.instance.resetForTests();
    final lookApi = _CountingScrubFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-empty-coord'));
    for (var i = 0; i < 4; i++) {
      ClassicStripScrubCoordinator.instance.enqueueShot(
        encodeShotDataUrl: () async => '',
        enableScrub: false,
      );
    }
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: lookApi,
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await vm.preparePreview();
    // Empty coordinator payloads are ignored; look API cleans instead.
    expect(lookApi.cleanCalls, greaterThan(0));
    expect(vm.previewCleaned, isTrue);
  });

  test('FotoFlashbackFilterViewModel preparePreview survives API throw',
      () async {
    ClassicStripScrubCoordinator.instance.resetForTests();
    final api = _ThrowingScrubFakeApi();
    SessionManager().clearSession();
    SessionManager().setSessionFromResponse(_sessionJson('sess-throw-scrub'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    // Allow the unawaited prepare from loadFilters to finish first.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.cleanCalls, greaterThan(0));
    expect(vm.previewCleaned, isFalse);
    expect(vm.isPreparingPreview, isFalse);
    await vm.preparePreview();
    expect(vm.previewCleaned, isFalse);
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
      overlayCleanupBuildGate: true,
    );

    expect(vm.canCompose, isTrue);
    expect(vm.filters, isEmpty);
    expect(vm.selectedFilter, isNull);
    await vm.loadFilters();
    expect(vm.filters, hasLength(3));
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

    // Overlay polish runs on the look screen; compose skips a second Gemini
    // AF clean when preview already finished.
    await vm.preparePreview();
    expect(vm.previewCleaned, isTrue);
    expect(vm.imageDataUrls.every((u) => u.endsWith('_clean')), isTrue);

    final image = await vm.compose();
    expect(image, isNotNull);
    expect(image!.imageUrl, 'https://example.com/strip.jpg');
    expect(image.isSelected, isTrue);
    expect(vm.composeResult, isNotNull);
    expect(api.composeCalls, 1);
    expect(api.lastComposeFilter, 'mono');
    expect(
      api.lastComposeTimeout,
      AppConstants.kClassicStripComposeTimeout,
    );
    expect(api.lastCleanOverlays, isFalse);
    expect(api.lastFrame, 'noir');
    expect(api.lastSticker, kDefaultStripStickerId);
    expect(api.lastPlacements, hasLength(kStripShotCount));
  });

  test('FotoFlashbackFilterViewModel skips cleanup when scrub is OFF', () async {
    final api = _StripFakeApi(enableOsdScrub: false);
    SessionManager().setSessionFromResponse(_sessionJson('sess-scrub-off'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    expect(vm.classicOverlayCleanupEnabled, isFalse);
    await vm.preparePreview();
    expect(vm.previewCleaned, isFalse);
    expect(vm.imageDataUrls.any((u) => u.endsWith('_clean')), isFalse);

    final image = await vm.compose();
    expect(image, isNotNull);
    expect(api.lastCleanOverlays, isFalse);
  });

  test('FotoFlashbackFilterViewModel scribble draw/undo/clear', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
      overlayCleanupBuildGate: true,
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
    vm.addSticker('flowers');
    expect(vm.stickerPlacements, hasLength(kStripShotCount * 2));
    expect(
      vm.stickerPlacements.where((p) => p.type == 'flowers'),
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

    final singleVm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['data:image/jpeg;base64,/9j/4AAQ'],
      apiService: _StripFakeApi(),
    );
    expect(singleVm.isSingleClassic, isTrue);
    expect(singleVm.canCompose, isTrue);
    singleVm.addSticker('hearts');
    expect(singleVm.stickerPlacements, hasLength(1));

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
    expect(loadFail.filters, isNotEmpty);
    expect(loadFail.canCompose, isTrue);

    final apiBoom = _StripFakeApi(throwGenericLoad: true);
    final loadBoom = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: apiBoom,
    );
    await loadBoom.loadFilters();
    expect(loadBoom.errorMessage, contains('load boom'));
    expect(loadBoom.filters, isNotEmpty);

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

  test('FotoFlashbackFilterViewModel preview grade and sheet frames', () async {
    final api = _SheetFramesFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-sheet'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
    );
    await vm.loadFilters();
    expect(vm.wysiwygLayout.gridTitle, isNotEmpty);
    expect(vm.frames.map((f) => f.id), contains('grid_2x2'));

    // Look browser stays on Flutter ColorFilters until print twin warms.
    await vm.preparePreview();
    await vm.refreshPreviewGrade();
    expect(vm.previewImagesAreGraded, isFalse);
    expect(vm.previewImageDataUrls, vm.imageDataUrls);
    expect(vm.isRefreshingLookPreview, isFalse);

    await vm.refreshComposePreview();
    expect(vm.lookComposePreviewUrl, 'https://example.com/strip.jpg');
    expect(vm.isWarmingPrintPreview, isFalse);

    vm.selectFrame('grid_2x2');
    expect(vm.selectedFrame?.id, 'grid_2x2');
    vm.addSticker('sparkles');
    expect(vm.stickerPlacements, isNotEmpty);
    vm.selectFrame('classic');
    expect(vm.stickerPlacements, isEmpty);

    vm.selectFrame('romantic');
    vm.addSticker('flowers');
    vm.selectFrame('polaroid');
    vm.clearStickers();
    vm.addSticker('stars');
    expect(vm.stickerPlacements, hasLength(kStripShotCount));
  });

  test('FotoFlashbackFilterViewModel draw mode and scrub dots', () async {
    final api = _StripFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-draw'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      shotCleaned: const [true, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    expect(vm.scrubDotStatuses.first, ClassicScrubDotStatus.cleaned);

    vm.setDrawMode(true);
    vm.beginScribble(0.15, 0.15);
    vm.extendScribble(0.25, 0.25);
    expect(vm.scribbles, hasLength(1));
    expect(vm.canUndoScribble, isTrue);
    vm.undoScribble();
    expect(vm.scribbles, isEmpty);

    vm.beginScribble(0.1, 0.1);
    vm.extendScribble(0.2, 0.2);
    vm.setDrawMode(false);
    expect(vm.drawMode, isFalse);
    expect(vm.scribbles, hasLength(1));

    vm.setPenColor('#FFFFFF');
    expect(vm.penColor, '#FFFFFF');
    vm.setPenColor('invalid');
    expect(vm.penColor, '#FFFFFF');
  });

  test('FotoFlashbackFilterViewModel single classic hides sheet frames', () async {
    final api = _SheetFramesFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['data:image/jpeg;base64,/9j/4AAQ'],
      apiService: api,
    );
    await vm.loadFilters();
    expect(vm.isSingleClassic, isTrue);
    expect(vm.frames.any((f) => f.id == 'grid_2x2'), isFalse);
    vm.selectPrintOrientation(PrintOrientation.landscape);
    expect(vm.printOrientation, PrintOrientation.landscape);
    vm.selectPrintOrientation(PrintOrientation.landscape);
    vm.addSticker('flowers');
    expect(vm.stickerPlacements, hasLength(1));
  });

  test('FotoFlashbackFilterViewModel refreshPreviewGrade no-ops off strip count',
      () async {
    final single = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['data:image/jpeg;base64,/9j/4AAQ'],
      apiService: _StripFakeApi(),
    );
    await single.refreshPreviewGrade();
    expect(single.previewImagesAreGraded, isFalse);
  });

  test('FotoFlashbackFilterViewModel single classic resets sheet frame on load',
      () async {
    final api = _SheetOnlyFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['data:image/jpeg;base64,/9j/4AAQ'],
      apiService: api,
    );
    await vm.loadFilters();
    expect(vm.selectedFrameId, isNot('grid_2x2'));
    expect(vm.previewImageDataUrls, vm.imageDataUrls);
    expect(vm.canUndoScribble, isFalse);
  });

  test('FotoFlashbackFilterViewModel scrub dots show failed after pass', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-dots'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: _EmptyScrubFakeApi(),
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await vm.preparePreview();
    expect(vm.scrubDotStatuses, everyElement(ClassicScrubDotStatus.failed));
  });

  test('FotoFlashbackFilterViewModel plain sheet spawn fallback', () async {
    final api = _PlainSheetFakeApi();
    SessionManager().setSessionFromResponse(_sessionJson('sess-plain'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    vm.selectFrame('custom_sheet');
    vm.addSticker('hearts');
    expect(vm.stickerPlacements, hasLength(kStripShotCount));
  });

  test('FotoFlashbackFilterViewModel defers grade when cache warm', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-grade-cache'));
    final api = _CountingGradeFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    await vm.refreshPreviewGrade();
    await vm.refreshPreviewGrade();
    expect(api.gradeCalls, 1);
  });

  test('FotoFlashbackFilterViewModel 4-shot compose compacts large uploads',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-compact-4'));
    final api = _StripFakeApi();
    final fat = 'data:image/jpeg;base64,${'A' * 60000}';
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, fat),
      apiService: api,
      overlayCleanupAlreadyDone: true,
      overlayCleanupBuildGate: false,
    );
    final image = await vm.compose();
    expect(image, isNotNull);
    expect(api.lastComposeImages, hasLength(4));
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel 4-shot compose skips a second scrub',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-no-rescrub'));
    final api = _ThrowingScrubFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: api,
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.preparePreview();
    expect(vm.previewCleaned, isFalse);
    final afterPrep = api.cleanCalls;
    expect(afterPrep, greaterThan(0));
    final image = await vm.compose();
    expect(image, isNotNull);
    expect(api.cleanCalls, afterPrep);
    expect(
      api.lastComposeTimeout,
      AppConstants.kClassicStripComposeTimeout,
    );
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel compose prepares uncleaned preview', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-compose-prep'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: _StripFakeApi(),
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    final image = await vm.compose();
    expect(image, isNotNull);
    expect(vm.previewCleaned, isTrue);
  });

  test('FotoFlashbackFilterViewModel single classic clears sheet frame on load',
      () async {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: const ['data:image/jpeg;base64,/9j/4AAQ'],
      apiService: _SheetFramesFakeApi(),
    );
    vm.selectedFrameIdForTests = 'grid_2x2';
    await vm.loadFilters();
    expect(vm.selectedFrameId, 'classic');
  });

  test('FotoFlashbackFilterViewModel exposes pen width and initial scrub dots',
      () async {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: _StripFakeApi(),
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    expect(vm.penWidth, 0.02);
    expect(vm.scrubDotStatuses, everyElement(ClassicScrubDotStatus.pending));
  });

  test('FotoFlashbackFilterViewModel reports grading preview state', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-grading-flag'));
    final api = _SlowGradeFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: api,
    );
    await vm.loadFilters();
    final gradeFuture = vm.refreshPreviewGrade();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(vm.isGradingPreview, isTrue);
    // Grade no longer counts as "Polishing photos…".
    expect(vm.isPreparingPreview, isFalse);
    expect(vm.canCompose, isTrue);
    await gradeFuture;
  });

  test('FotoFlashbackFilterViewModel pending scrub dots while preparing', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-pending-dots'));
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
      apiService: _SlowScrubFakeApi(),
      shotCleaned: const [false, false, false, false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    final prepare = vm.preparePreview();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.scrubDotStatuses[1], ClassicScrubDotStatus.pending);
    await prepare;
  });

  test('FotoFlashbackFilterViewModel canUndo with active scribble point', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
      overlayCleanupBuildGate: true,
    );
    vm.setDrawMode(true);
    vm.beginScribble(0.2, 0.2);
    expect(vm.canUndoScribble, isTrue);
  });

  test('FotoFlashbackFilterViewModel exposes idle compose-refresh getters', () {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _StripFakeApi(),
    );
    expect(vm.isRefreshingComposePreview, isFalse);
    expect(vm.isRefreshingLookPreview, isFalse);
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel falls back when catalog has no filters',
      () async {
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
      apiService: _EmptyFiltersFakeApi(),
    );
    await vm.loadFilters();
    expect(vm.filters, isNotEmpty);
    expect(vm.errorMessage, AppStrings.flashbackFiltersLoadTimeout);
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel catalog load timeout uses fallback', () {
    fakeAsync((async) {
      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List.filled(4, 'data:image/jpeg;base64,/9j/4AAQ'),
        apiService: _HangingCatalogFakeApi(),
      );
      unawaited(vm.loadFilters());
      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(vm.filters, isNotEmpty);
      expect(vm.errorMessage, AppStrings.flashbackFiltersLoadTimeout);
      vm.dispose();
    });
  });

  test('FotoFlashbackFilterViewModel adopt scrub times out and re-posts', () {
    fakeAsync((async) {
      ClassicStripScrubCoordinator.instance.resetForTests();
      SessionManager().setSessionFromResponse(_sessionJson('sess-adopt-to'));
      final hang = Completer<String>();
      for (var i = 0; i < 4; i++) {
        ClassicStripScrubCoordinator.instance.enqueueShot(
          encodeShotDataUrl: () => hang.future,
          enableScrub: true,
          apiService: _StripFakeApi(),
        );
      }
      final api = _CountingScrubFakeApi();
      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
        apiService: api,
        shotCleaned: const [false, false, false, false],
        overlayCleanupBuildGate: true,
      );
      unawaited(vm.preparePreview());
      async.elapse(const Duration(seconds: 45));
      async.flushMicrotasks();
      // First shot timed out adopt → API clean; remaining shots still pending.
      expect(api.cleanCalls, greaterThan(0));
      hang.complete('data:image/jpeg;base64,raw');
      async.flushMicrotasks();
      vm.dispose();
      ClassicStripScrubCoordinator.instance.resetForTests();
    });
  });

  test('FotoFlashbackFilterViewModel compose survives preparePreview timeout',
      () {
    fakeAsync((async) {
      SessionManager().setSessionFromResponse(_sessionJson('sess-prep-to'));
      final api = _HangingScrubComposeFakeApi();
      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
        apiService: api,
        shotCleaned: const [false, false, false, false],
        overlayCleanupBuildGate: true,
      );
      late GeneratedImage? image;
      unawaited(vm.compose().then((v) => image = v));
      async.elapse(const Duration(seconds: 45));
      async.flushMicrotasks();
      // After prepare timeout, composeStrip still runs (skipBake for 4-shot).
      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();
      expect(image, isNotNull);
      vm.dispose();
    });
  });

  test('FotoFlashbackFilterViewModel compose times out on hanging strip API',
      () {
    fakeAsync((async) {
      SessionManager().setSessionFromResponse(_sessionJson('sess-compose-to'));
      final api = _HangingComposeOnlyFakeApi();
      final vm = FotoFlashbackFilterViewModel(
        theme: stripTheme,
        imageDataUrls: List.filled(4, 'data:image/jpeg;base64,shot'),
        apiService: api,
        overlayCleanupAlreadyDone: true,
        overlayCleanupBuildGate: false,
      );
      late GeneratedImage? image;
      unawaited(vm.compose().then((v) => image = v));
      async.elapse(AppConstants.kClassicStripComposeTimeout);
      async.flushMicrotasks();
      expect(image, isNull);
      expect(vm.errorMessage, AppStrings.flashbackComposeFailed);
      vm.dispose();
    });
  });

  test('FotoFlashbackFilterViewModel 1-shot warms, reuses, and skips look bake',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-one-warm'));
    final api = _StripFakeApi();
    final url = _tinyJpegDataUrl();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [url],
      apiService: api,
      overlayCleanupBuildGate: false,
    );
    await vm.loadFilters();
    vm.setDrawMode(true);
    vm.beginScribble(0.1, 0.1);
    vm.extendScribble(0.2, 0.2);
    vm.endScribble();
    expect(vm.scribbles, hasLength(1));

    await vm.refreshComposePreview();
    expect(vm.lookComposePreviewUrl, isNotNull);
    expect(api.composeCalls, 1);

    // Cache hit on second warm with same fingerprint.
    await vm.refreshComposePreview();
    expect(api.composeCalls, 1);

    // Scribble change invalidates fingerprint; skip-bake still POSTs look id.
    vm.beginScribble(0.3, 0.3);
    vm.extendScribble(0.4, 0.4);
    vm.endScribble();
    await vm.refreshComposePreview();
    expect(api.composeCalls, 2);

    final image = await vm.compose();
    expect(image, isNotNull);
    // Reuse warmed preview — no third compose POST.
    expect(api.composeCalls, 2);
    expect(api.lastComposeFilter, kDefaultStripFilterId);
    expect(
      api.lastComposeTimeout,
      AppConstants.kClassicSingleComposeTimeout,
    );
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel 1-shot compose skips overlay prepare',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-one-skip-prep'));
    final api = _HangingScrubComposeFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      apiService: api,
      shotCleaned: const [false],
      overlayCleanupBuildGate: true,
    );
    await vm.loadFilters();
    final image = await vm.compose().timeout(const Duration(seconds: 8));
    expect(image, isNotNull);
    expect(
      api.lastComposeTimeout,
      AppConstants.kClassicSingleComposeTimeout,
    );
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel joins in-flight compose warm', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-join-warm'));
    final gate = Completer<void>();
    final api = _GatedComposeFakeApi(gate);
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      apiService: api,
      overlayCleanupBuildGate: false,
    );
    await vm.loadFilters();
    final warm = vm.refreshComposePreview();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.isWarmingPrintPreview, isTrue);

    final composeFuture = vm.compose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();
    final image = await composeFuture;
    await warm;
    expect(image, isNotNull);
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel warm join timeout is fail-open', () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-warm-to'));
    FotoFlashbackFilterViewModel.composeWarmJoinTimeoutForTest =
        const Duration(milliseconds: 30);
    final gate = Completer<void>();
    final api = _GatedComposeFakeApi(gate);
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      apiService: api,
      overlayCleanupBuildGate: false,
    );
    await vm.loadFilters();
    unawaited(vm.refreshComposePreview());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final composeFuture = vm.compose();
    // Warm still gated; join times out, then compose posts itself.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    final image = await composeFuture;
    expect(image, isNotNull);
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel schedules warm after orientation change',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-orient-warm'));
    final api = _StripFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      apiService: api,
      overlayCleanupBuildGate: false,
    );
    await vm.loadFilters();
    vm.selectPrintOrientation(PrintOrientation.landscape);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(api.composeCalls, greaterThan(0));
    expect(vm.lookComposePreviewUrl, isNotNull);
    vm.dispose();
  });

  test('FotoFlashbackFilterViewModel compose starts warm when none in flight',
      () async {
    SessionManager().setSessionFromResponse(_sessionJson('sess-start-warm'));
    final api = _StripFakeApi();
    final vm = FotoFlashbackFilterViewModel(
      theme: stripTheme,
      imageDataUrls: [_tinyJpegDataUrl()],
      apiService: api,
      overlayCleanupBuildGate: false,
    );
    // No loadFilters → no debounce warm; compose itself kicks refreshComposePreview.
    final image = await vm.compose();
    expect(image, isNotNull);
    expect(api.composeCalls, greaterThan(0));
    vm.dispose();
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

class _FlakyScrubFakeApi extends _StripFakeApi {
  bool succeedRemaining = false;

  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    if (!succeedRemaining) {
      return StripOverlayCleanResult(
        images: List<String>.from(images),
        cleanedFlags: List<bool>.filled(images.length, false),
      );
    }
    return super.cleanStripOverlays(sessionId: sessionId, images: images);
  }
}

class _FailingScrubFakeApi extends _StripFakeApi {
  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    return StripOverlayCleanResult(
      images: List<String>.from(images),
      cleanedFlags: List<bool>.filled(images.length, false),
    );
  }
}

class _CountingScrubFakeApi extends _StripFakeApi {
  int cleanCalls = 0;

  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    cleanCalls++;
    return super.cleanStripOverlays(sessionId: sessionId, images: images);
  }
}

class _EmptyScrubFakeApi extends _StripFakeApi {
  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    return const StripOverlayCleanResult(
      images: [''],
      cleanedFlags: [false],
    );
  }
}

class _ThrowingScrubFakeApi extends _StripFakeApi {
  int cleanCalls = 0;

  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    cleanCalls++;
    throw Exception('scrub boom');
  }
}

class _StripFakeApi extends FakeApiService {
  _StripFakeApi({
    this.failCompose = false,
    this.failLoad = false,
    this.throwGenericLoad = false,
    this.throwGenericCompose = false,
    this.monoOnly = false,
    this.altChromeOnly = false,
    this.enableOsdScrub = true,
  });

  final bool failCompose;
  final bool failLoad;
  final bool throwGenericLoad;
  final bool throwGenericCompose;
  final bool monoOnly;
  final bool altChromeOnly;
  final bool enableOsdScrub;
  int composeCalls = 0;
  String? lastComposeFilter;
  List<String>? lastComposeImages;
  String? lastFrame;
  String? lastSticker;
  List<StripStickerPlacement>? lastPlacements;
  List<StripScribbleStroke>? lastScribbles;
  bool? lastCleanOverlays;
  Duration? lastComposeTimeout;

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
      'features': {
        'enableOsdScrub': enableOsdScrub,
        'enableSurpriseMeAi': false,
      },
      'filters': [
        {
          'id': 'clean',
          'name': 'Clean',
          'description': 'No grade',
          'cssFilter': 'none',
        },
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
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    final out = images
        .map((e) => e.endsWith('_clean') ? e : '${e}_clean')
        .toList();
    return StripOverlayCleanResult(
      images: out,
      cleanedFlags: List<bool>.filled(out.length, true),
    );
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
    composeCalls++;
    lastComposeFilter = filter;
    lastComposeImages = List<String>.from(images);
    lastCleanOverlays = cleanOverlays;
    lastFrame = frame;
    lastSticker = sticker;
    lastPlacements = List<StripStickerPlacement>.from(stickerPlacements);
    lastScribbles = List<StripScribbleStroke>.from(scribbles);
    lastComposeTimeout = timeout;
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
}

class _SlowGradeFakeApi extends _StripFakeApi {
  @override
  Future<List<String>> gradeStripPreview({
    required String sessionId,
    required List<String> images,
    String filter = kDefaultStripFilterId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.gradeStripPreview(
      sessionId: sessionId,
      images: images,
      filter: filter,
    );
  }
}

class _CountingGradeFakeApi extends _StripFakeApi {
  int gradeCalls = 0;

  @override
  Future<List<String>> gradeStripPreview({
    required String sessionId,
    required List<String> images,
    String filter = kDefaultStripFilterId,
  }) async {
    gradeCalls++;
    return super.gradeStripPreview(
      sessionId: sessionId,
      images: images,
      filter: filter,
    );
  }
}

class _SlowScrubFakeApi extends _StripFakeApi {
  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return super.cleanStripOverlays(sessionId: sessionId, images: images);
  }
}

class _PlainSheetFakeApi extends _SheetFramesFakeApi {
  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
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
        {'id': 'custom_sheet', 'name': 'Custom', 'description': 'Custom'},
      ],
      'stickers': [
        {'id': 'hearts', 'name': 'Hearts', 'description': 'Hearts'},
      ],
    });
  }
}

class _SheetOnlyFakeApi extends _StripFakeApi {
  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
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
        {'id': 'grid_2x2', 'name': 'Grid', 'description': 'Grid'},
      ],
    });
  }
}

class _SheetFramesFakeApi extends _StripFakeApi {
  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
    return StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'features': {'enableOsdScrub': true},
      'filters': [
        {
          'id': 'classic_warm',
          'name': 'Classic Warm',
          'description': 'Warm',
          'cssFilter': 'none',
        },
      ],
      'frames': [
        {'id': 'classic', 'name': 'Classic', 'description': 'White'},
        {'id': 'grid_2x2', 'name': 'Grid', 'description': 'Grid'},
        {'id': 'romantic', 'name': 'Romantic', 'description': 'Romantic'},
        {'id': 'polaroid', 'name': 'Polaroid', 'description': 'Polaroid'},
      ],
      'stickers': [
        {'id': 'sparkles', 'name': 'Sparkles', 'description': 'Sparkles'},
        {'id': 'stars', 'name': 'Stars', 'description': 'Stars'},
        {'id': 'flowers', 'name': 'Flowers', 'description': 'Flowers'},
      ],
      'layout': {
        'grid2x2': {'title': 'Together', 'subtitle': 'Moments'},
      },
    });
  }
}

class _EmptyFiltersFakeApi extends _StripFakeApi {
  @override
  Future<StripFiltersCatalog> fetchStripFilters() async {
    return StripFiltersCatalog.fromJson({
      'brand': 'FotoFlashback',
      'shotCount': 4,
      'filters': <Map<String, dynamic>>[],
    });
  }
}

class _HangingCatalogFakeApi extends _StripFakeApi {
  @override
  Future<StripFiltersCatalog> fetchStripFilters() => Completer<StripFiltersCatalog>().future;
}

class _HangingScrubComposeFakeApi extends _StripFakeApi {
  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) {
    return Completer<StripOverlayCleanResult>().future;
  }
}

class _HangingComposeOnlyFakeApi extends _StripFakeApi {
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
  }) {
    return Completer<StripComposeResult>().future;
  }
}

class _GatedComposeFakeApi extends _StripFakeApi {
  _GatedComposeFakeApi(this.gate);

  final Completer<void> gate;

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
    await gate.future;
    return super.composeStrip(
      sessionId: sessionId,
      images: images,
      filter: filter,
      frame: frame,
      sticker: sticker,
      stickerPlacements: stickerPlacements,
      scribbles: scribbles,
      cleanOverlays: cleanOverlays,
      orientation: orientation,
      timeout: timeout,
    );
  }
}
