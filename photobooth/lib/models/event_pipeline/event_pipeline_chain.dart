import 'event_pipeline_settings.dart';

/// Renders a resolved step list as the one line an operator reads before the
/// chain is frozen onto an item, e.g. `AI → Frame → Print s4x6 · 2 copies`.
///
/// Pure string work, deliberately kept out of any widget: the import footer, the
/// event settings screen and the hub all show the same sentence, and it has to
/// read identically in each.
abstract final class EventPipelineChain {
  static String labelFor(String step) {
    switch (step) {
      case EventPipelineStep.ai:
        return 'AI';
      case EventPipelineStep.frame:
        return 'Frame';
      case EventPipelineStep.print:
        return 'Print';
      default:
        return step;
    }
  }

  /// Human summary of the chain, e.g. `AI → Frame → Print 4x6 · 2 copies`.
  static String describe(List<String> steps, int copies, String printSize) {
    if (steps.isEmpty) return 'Nothing will run — imports are stored only.';
    final parts = steps.map(labelFor).toList();
    final buffer = StringBuffer(parts.join(' → '));
    if (steps.contains(EventPipelineStep.print)) {
      buffer.write(' $printSize');
      buffer.write(copies == 1 ? ' · 1 copy' : ' · $copies copies');
    }
    return buffer.toString();
  }
}
