import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/generation_wait_helpers.dart';
import 'package:photobooth/screens/photo_generate/generation_wait_story_helpers.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:camera/camera.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';

void main() {
  const theme = ThemeModel(
    id: 't1',
    categoryId: 'c1',
    name: 'Vintage Noir',
    description: 'd',
    promptText: 'p',
    sampleImageUrl: 'https://example.com/sample.jpg',
  );

  final photo = PhotoModel(
    id: 'p1',
    imageFile: XFile('/tmp/photo_test.jpg'),
    capturedAt: DateTime.utc(2026, 1, 2),
  );

  group('generationWaitActIndex', () {
    test('starts in studying act', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      final presentation = resolveGenerationWaitPresentation(
        vm,
        commentaryEnabled: true,
      );
      expect(generationWaitActIndex(vm, presentation), 0);
      expect(
        generationWaitActHeadline(vm, presentation),
        kGenerationWaitActHeadlines.first,
      );
    });
  });

  group('generationWaitDynamicQuote', () {
    test('rotates every 5 seconds', () {
      expect(
        generationWaitDynamicQuote(0),
        kGenerationWaitDynamicQuotes.first,
      );
      expect(
        generationWaitDynamicQuote(5),
        kGenerationWaitDynamicQuotes[1],
      );
    });
  });

  group('generationWaitFaceScanCompletedCount', () {
    test('adds one line per elapsed second', () {
      expect(generationWaitFaceScanCompletedCount(3), 3);
      expect(
        generationWaitFaceScanCompletedCount(20),
        kGenerationWaitFaceScanLines.length,
      );
    });
  });

  group('resolveGenerationWaitRewardChecklist', () {
    test('first beat is active before any progress', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      final presentation = resolveGenerationWaitPresentation(
        vm,
        commentaryEnabled: true,
      );
      final beats = resolveGenerationWaitRewardChecklist(vm, presentation);
      expect(beats.first.state, GenerationWaitBeatState.active);
      expect(beats.last.state, GenerationWaitBeatState.pending);
    });
  });

  group('generationWaitShowFaceScanChecklist', () {
    test('true during early anticipation', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      vm.prepareToAddStyle(theme);
      final presentation = resolveGenerationWaitPresentation(
        vm,
        commentaryEnabled: true,
      );
      expect(
        generationWaitShowFaceScanChecklist(vm, presentation),
        isTrue,
      );
    });
  });
}
