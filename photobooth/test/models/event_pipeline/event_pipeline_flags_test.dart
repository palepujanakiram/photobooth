import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_flags.dart';

void main() {
  group('EventPipelineFlags.fromEventJson', () {
    test('reads camelCase keys', () {
      final f = EventPipelineFlags.fromEventJson(const {
        'pipelineEnabled': true,
        'offlineMode': true,
        'aiEnabled': false,
        'themeId': 'theme-1',
        'frameEnabled': true,
        'frameId': 'frame-9',
        'autoPrint': false,
        'defaultCopies': 2,
        'printSize': 's6x8',
        'mirrorEnabled': false,
      });
      expect(f.pipelineEnabled, isTrue);
      expect(f.offlineMode, isTrue);
      expect(f.aiEnabled, isFalse);
      expect(f.themeId, 'theme-1');
      expect(f.frameEnabled, isTrue);
      expect(f.frameId, 'frame-9');
      expect(f.autoPrint, isFalse);
      expect(f.defaultCopies, 2);
      expect(f.printSize, 's6x8');
      expect(f.mirrorEnabled, isFalse);
    });

    test('reads snake_case keys', () {
      final f = EventPipelineFlags.fromEventJson(const {
        'pipeline_enabled': true,
        'ai_enabled': true,
        'theme_id': 'theme-2',
        'frame_enabled': false,
        'frame_id': 'frame-3',
        'auto_print': true,
        'default_copies': 3,
        'print_size': 's5x7',
        'offline_mode': false,
        'mirror_enabled': true,
      });
      expect(f.pipelineEnabled, isTrue);
      expect(f.aiEnabled, isTrue);
      expect(f.themeId, 'theme-2');
      expect(f.frameEnabled, isFalse);
      expect(f.frameId, 'frame-3');
      expect(f.autoPrint, isTrue);
      expect(f.defaultCopies, 3);
      expect(f.printSize, 's5x7');
      expect(f.offlineMode, isFalse);
      expect(f.mirrorEnabled, isTrue);
    });

    test('unwraps a nested event object', () {
      final f = EventPipelineFlags.fromEventJson(const {
        'event': {'pipelineEnabled': true, 'themeId': 'nested'},
      });
      expect(f.pipelineEnabled, isTrue);
      expect(f.themeId, 'nested');
    });

    test('a nested pipeline object wins over root keys', () {
      final f = EventPipelineFlags.fromEventJson(const {
        'aiEnabled': false,
        'pipeline': {'aiEnabled': true, 'themeId': 'scoped'},
      });
      expect(f.aiEnabled, isTrue);
      expect(f.themeId, 'scoped');
    });

    test('absent fields stay null so they can inherit', () {
      final f = EventPipelineFlags.fromEventJson(const {'code': 'GALA'});
      expect(f.isEmpty, isTrue);
      expect(f.pipelineEnabled, isNull);
      expect(f.aiEnabled, isNull);
    });

    test('an explicit false is kept, not treated as absent', () {
      final f = EventPipelineFlags.fromEventJson(const {'aiEnabled': false});
      expect(f.aiEnabled, isFalse);
      expect(f.isEmpty, isFalse);
    });

    test('blank strings read as null rather than empty ids', () {
      final f = EventPipelineFlags.fromEventJson(const {
        'themeId': '   ',
        'frameId': '',
      });
      expect(f.themeId, isNull);
      expect(f.frameId, isNull);
    });

    test('copies below 1 are unset, not honoured', () {
      expect(
        EventPipelineFlags.fromEventJson(const {'defaultCopies': 0})
            .defaultCopies,
        isNull,
      );
      expect(
        EventPipelineFlags.fromEventJson(const {'defaultCopies': -3})
            .defaultCopies,
        isNull,
      );
      expect(
        EventPipelineFlags.fromEventJson(const {'defaultCopies': 1})
            .defaultCopies,
        1,
      );
    });

    test('every field screens spec §12 asks the backend for is parsed', () {
      // The "Missing — needed for read-only settings" table. If the backend
      // starts sending one of these and this test still passes, the device
      // honours it with no further change.
      final flags = EventPipelineFlags.fromEventJson(const {
        'aiEnabled': true,
        'themeId': 'theme-7',
        'frameEnabled': true,
        'frameId': 'frame-3',
        'autoPrint': false,
        'defaultCopies': 2,
        'printSize': 's6x8',
      });
      expect(flags.aiEnabled, isTrue);
      expect(flags.themeId, 'theme-7');
      expect(flags.frameEnabled, isTrue);
      expect(flags.frameId, 'frame-3');
      expect(flags.autoPrint, isFalse);
      expect(flags.defaultCopies, 2);
      expect(flags.printSize, 's6x8');
    });

    test('copyWith replaces only what it is given', () {
      const original = EventPipelineFlags(
        pipelineEnabled: true,
        aiEnabled: true,
        defaultCopies: 2,
      );
      final updated = original.copyWith(themeId: 'theme-a');
      expect(updated.themeId, 'theme-a');
      expect(updated.pipelineEnabled, isTrue);
      expect(updated.aiEnabled, isTrue);
      expect(updated.defaultCopies, 2);
    });

    test('copyWith with nothing set is an unchanged copy', () {
      const original = EventPipelineFlags(
        pipelineEnabled: true,
        offlineMode: true,
        aiEnabled: false,
        themeId: 't',
        frameEnabled: true,
        frameId: 'f',
        autoPrint: true,
        defaultCopies: 3,
        printSize: 's5x7',
        mirrorEnabled: false,
      );
      expect(original.copyWith().toJson(), original.toJson());
    });

    test('toJson omits nulls and round-trips', () {
      const original = EventPipelineFlags(pipelineEnabled: true, themeId: 't');
      final json = original.toJson();
      expect(json.containsKey('aiEnabled'), isFalse);
      final back = EventPipelineFlags.fromEventJson(json);
      expect(back.pipelineEnabled, isTrue);
      expect(back.themeId, 't');
      expect(back.aiEnabled, isNull);
    });
  });
}
