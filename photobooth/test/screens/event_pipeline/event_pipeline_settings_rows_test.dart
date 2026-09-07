import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/event_pipeline/event_pipeline_settings_rows.dart';

void main() {
  group('EventPipelineChainPreview.describe', () {
    test('full chain reads as the operator expects', () {
      expect(
        EventPipelineChainPreview.describe(
          const ['ai', 'frame', 'print'],
          1,
          's4x6',
        ),
        'AI → Frame → Print s4x6 · 1 copy',
      );
    });

    test('pluralises copies', () {
      expect(
        EventPipelineChainPreview.describe(const ['print'], 3, 's6x8'),
        'Print s6x8 · 3 copies',
      );
    });

    test('omits print size and copies when printing is not in the chain', () {
      expect(
        EventPipelineChainPreview.describe(const ['ai', 'frame'], 2, 's4x6'),
        'AI → Frame',
      );
    });

    test('an empty chain says imports are stored only', () {
      expect(
        EventPipelineChainPreview.describe(const [], 1, 's4x6'),
        'Nothing will run — imports are stored only.',
      );
    });
  });

  group('EventPipelineChainPreview.labelFor', () {
    test('maps known steps to display labels', () {
      expect(EventPipelineChainPreview.labelFor('ai'), 'AI');
      expect(EventPipelineChainPreview.labelFor('frame'), 'Frame');
      expect(EventPipelineChainPreview.labelFor('print'), 'Print');
    });

    test('falls back to the raw value for an unknown step', () {
      expect(EventPipelineChainPreview.labelFor('teleport'), 'teleport');
    });
  });
}
