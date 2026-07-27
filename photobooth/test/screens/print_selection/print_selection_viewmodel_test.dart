import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/print_selection/print_selection_viewmodel.dart';
import 'package:photobooth/services/print_selection_coordinator.dart';
import 'package:photobooth/utils/constants.dart';

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
