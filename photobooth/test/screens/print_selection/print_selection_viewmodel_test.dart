import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/print_selection/print_selection_viewmodel.dart';
import 'package:photobooth/services/app_settings_manager.dart';
import 'package:photobooth/services/print_selection_coordinator.dart';
import 'package:photobooth/utils/constants.dart';

import '../../fakes/fake_api_service.dart';
import '../../fixtures/theme_fixtures.dart';

void main() {
  tearDown(() {
    PrintSelectionCoordinator.instance.clear();
  });

  GeneratedImage strip() => GeneratedImage(
        id: 'strip',
        imageUrl: 'https://example.com/strip.jpg',
        theme: sampleTheme('strip'),
        isSelected: true,
        printSize: AppConstants.kPrintSizeStripDual2x6,
      );

  GeneratedImage ai(String id) => GeneratedImage(
        id: id,
        imageUrl: 'https://example.com/$id.jpg',
        theme: sampleTheme(id),
        isSelected: true,
        printSize: AppConstants.kPrintSizePortrait4x6,
      );

  test('coordinator seeds and merges AI without duplicates', () {
    final c = PrintSelectionCoordinator.instance;
    c.seed(seedImages: [strip()], fromClassicStrip: true);
    c.markExploreMore();
    expect(c.shouldReturnFromGenerate, isTrue);

    c.mergeAiImages([ai('a1'), ai('a1')]);
    expect(c.images, hasLength(2));
    expect(c.awaitingExploreMoreReturn, isFalse);
  });

  test('print selection total uses base + additional copies', () {
    final vm = PrintSelectionViewModel(
      images: [strip(), ai('a1'), ai('a2')],
    );
    expect(vm.selectedCount, 3);
    // default 100 + 2 * 50 = 200
    expect(vm.selectedTotalPrice, 200);
    vm.dispose();
  });

  test('print selection total uses kiosk settings prices', () {
    final settings = _SeededAppSettingsManager(
      AppSettingsModel(
        parallelImageCount: 1,
        initialPrice: 250,
        additionalPrintPrice: 75,
      ),
    );
    final vm = PrintSelectionViewModel(
      images: [strip(), ai('a1')],
      appSettingsManager: settings,
    );
    // 250 + 75 = 325
    expect(vm.selectedTotalPrice, 325);
    vm.dispose();
  });

  test('strip cannot be the only deselected image', () {
    final vm = PrintSelectionViewModel(images: [strip()]);
    vm.toggleSelected('strip');
    expect(vm.selectedCount, 1);
    vm.dispose();
  });

  test('toggle deselects AI; reloadFromCoordinator refreshes list', () {
    final c = PrintSelectionCoordinator.instance;
    c.seed(seedImages: [strip(), ai('a1')], fromClassicStrip: true);
    final vm = PrintSelectionViewModel(
      images: [strip(), ai('a1')],
      stripPrintSize: AppConstants.kPrintSizeStripDual2x6,
      coordinator: c,
    );
    expect(vm.fromClassicStrip, isTrue);
    expect(vm.canContinue, isTrue);
    expect(vm.images, hasLength(2));
    expect(vm.isStripImage(strip()), isTrue);
    vm.toggleSelected('missing');
    vm.toggleSelected('a1');
    expect(vm.selectedCount, 1);
    expect(vm.selectedImages.single.id, 'strip');
    c.mergeAiImages([ai('a2')]);
    vm.reloadFromCoordinator();
    expect(vm.images.map((e) => e.id), containsAll(['strip', 'a1', 'a2']));
    vm.dispose();
  });

  test('isStripImage matches custom stripPrintSize; empty selection totals 0', () {
    final custom = GeneratedImage(
      id: 's',
      imageUrl: 'https://example.com/s.jpg',
      theme: sampleTheme('s'),
      isSelected: false,
      printSize: 'custom_strip',
    );
    final vm = PrintSelectionViewModel(
      images: [custom],
      stripPrintSize: 'custom_strip',
    );
    expect(vm.isStripImage(custom), isTrue);
    expect(vm.selectedTotalPrice, 0);
    expect(vm.canContinue, isFalse);
    vm.dispose();
  });
}

class _SeededAppSettingsManager extends AppSettingsManager {
  _SeededAppSettingsManager(this._seed)
      : super(
          apiService: FakeApiService(),
          resolveKioskCode: () async => null,
        );

  final AppSettingsModel _seed;

  @override
  AppSettingsModel? get settings => _seed;

  @override
  bool get hasSettings => true;
}
