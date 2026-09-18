import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/event_pipeline_chain.dart';

void main() {
  group('EventPipelineChain.describe', () {
    test('full chain reads as the operator expects', () {
      expect(
        EventPipelineChain.describe(
          const ['ai', 'frame', 'print'],
          1,
          's4x6',
        ),
        'AI → Frame → Print s4x6 · 1 copy',
      );
    });

    test('pluralises copies', () {
      expect(
        EventPipelineChain.describe(const ['print'], 3, 's6x8'),
        'Print s6x8 · 3 copies',
      );
    });

    test('omits print size and copies when printing is not in the chain', () {
      expect(
        EventPipelineChain.describe(const ['ai', 'frame'], 2, 's4x6'),
        'AI → Frame',
      );
    });

    test('an empty chain says imports are stored only', () {
      expect(
        EventPipelineChain.describe(const [], 1, 's4x6'),
        'Nothing will run — imports are stored only.',
      );
    });
  });

  group('EventPipelineChain.labelFor', () {
    test('maps known steps to display labels', () {
      expect(EventPipelineChain.labelFor('ai'), 'AI');
      expect(EventPipelineChain.labelFor('frame'), 'Frame');
      expect(EventPipelineChain.labelFor('print'), 'Print');
    });

    test('falls back to the raw value for an unknown step', () {
      expect(EventPipelineChain.labelFor('teleport'), 'teleport');
    });
  });
}
