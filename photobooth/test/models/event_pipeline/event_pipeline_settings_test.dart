import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_settings.dart';

EventPipelineSettings settings({
  bool aiEnabled = false,
  String? themeId,
  bool frameEnabled = false,
  String? frameId,
  bool autoPrint = false,
}) {
  return EventPipelineSettings(
    pipelineEnabled: true,
    offlineMode: false,
    aiEnabled: aiEnabled,
    themeId: themeId,
    frameEnabled: frameEnabled,
    frameId: frameId,
    autoPrint: autoPrint,
    defaultCopies: 1,
    printSize: 's4x6',
    qualityFactor: 1.0,
    mirrorEnabled: true,
    scanFolders: const ['DCIM'],
  );
}

void main() {
  group('EventPipelineStep', () {
    test('normalize keeps chain order regardless of input order', () {
      expect(
        EventPipelineStep.normalize(['print', 'ai', 'frame']),
        ['ai', 'frame', 'print'],
      );
    });

    test('normalize drops unknown steps so an old build cannot stall', () {
      expect(
        EventPipelineStep.normalize(['ai', 'teleport', 'print']),
        ['ai', 'print'],
      );
    });

    test('normalize de-duplicates', () {
      expect(EventPipelineStep.normalize(['ai', 'ai']), ['ai']);
    });
  });

  group('resolveSteps', () {
    test('full chain when everything is enabled and configured', () {
      final s = settings(
        aiEnabled: true,
        themeId: 't1',
        frameEnabled: true,
        frameId: 'f1',
        autoPrint: true,
      );
      expect(s.resolveSteps(), ['ai', 'frame', 'print']);
    });

    test('AI is dropped when enabled but no theme is configured', () {
      final s = settings(aiEnabled: true, autoPrint: true);
      expect(s.canRunAi, isFalse);
      expect(s.resolveSteps(), ['print']);
    });

    test('frame is dropped when enabled but no frame is configured', () {
      final s = settings(frameEnabled: true, autoPrint: true);
      expect(s.canRunFrame, isFalse);
      expect(s.resolveSteps(), ['print']);
    });

    test('a blank theme id counts as unconfigured', () {
      final s = settings(aiEnabled: true, themeId: '  ', autoPrint: true);
      expect(s.canRunAi, isFalse);
      expect(s.resolveSteps(), ['print']);
    });

    test('autoPrint off stops the chain before printing', () {
      final s = settings(frameEnabled: true, frameId: 'f1');
      expect(s.resolveSteps(), ['frame']);
    });

    test('everything off resolves to an empty chain', () {
      expect(settings().resolveSteps(), isEmpty);
    });
  });

  group('withoutAi', () {
    test('drops ai and keeps the rest in order', () {
      expect(
        EventPipelineSettings.withoutAi(['ai', 'frame', 'print']),
        ['frame', 'print'],
      );
    });

    test('leaves a chain that never had ai untouched', () {
      expect(
        EventPipelineSettings.withoutAi(['frame', 'print']),
        ['frame', 'print'],
      );
    });

    test('an ai-only chain becomes empty', () {
      expect(EventPipelineSettings.withoutAi(['ai']), isEmpty);
    });

    test('normalizes unknown steps out at the same time', () {
      expect(
        EventPipelineSettings.withoutAi(['ai', 'bogus', 'print']),
        ['print'],
      );
    });
  });

  group('EventPipelineDefaults', () {
    test('FRAME_ONLY turns AI off by default, case-insensitively', () {
      expect(
        const EventPipelineDefaults(photoMode: 'FRAME_ONLY').aiEnabledDefault,
        isFalse,
      );
      expect(
        const EventPipelineDefaults(photoMode: 'frame_only').aiEnabledDefault,
        isFalse,
      );
      expect(const EventPipelineDefaults().aiEnabledDefault, isTrue);
    });

    test('framing defaults on only when the event has frames', () {
      expect(const EventPipelineDefaults().frameEnabledDefault, isFalse);
      expect(
        const EventPipelineDefaults(frameCount: 2).frameEnabledDefault,
        isTrue,
      );
    });
  });

  test('copyWith replaces only what it is given', () {
    final s = settings(aiEnabled: true, themeId: 't1');
    final c = s.copyWith(autoPrint: true);
    expect(c.autoPrint, isTrue);
    expect(c.aiEnabled, isTrue);
    expect(c.themeId, 't1');
    expect(c.printSize, 's4x6');
  });
}
