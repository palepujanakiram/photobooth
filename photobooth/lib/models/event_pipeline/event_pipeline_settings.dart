/// Processing steps an item can be queued through, in chain order.
///
/// The string values are persisted in `evp_media_items.steps_json` and must stay
/// stable across releases — an in-flight event's frozen step list is read back
/// after a restart.
abstract final class EventPipelineStep {
  static const String ai = 'ai';
  static const String frame = 'frame';
  static const String print = 'print';

  /// Chain order. A resolved step list is always a subsequence of this.
  static const List<String> order = <String>[ai, frame, print];

  static bool isValid(String step) => order.contains(step);

  /// Keeps [steps] in chain order and drops anything unrecognised.
  ///
  /// Used when reading a frozen list back from the ledger: a build that no
  /// longer knows a step must not stall on it forever.
  static List<String> normalize(Iterable<String> steps) {
    final seen = steps.map((s) => s.trim()).toSet();
    return [for (final s in order) if (seen.contains(s)) s];
  }
}

/// Event context the pipeline defaults are derived from when neither the backend
/// nor a local override has an opinion.
class EventPipelineDefaults {
  const EventPipelineDefaults({
    this.photoMode = 'BOTH',
    this.frameCount = 0,
    this.printSize = 's4x6',
    this.printerEnabled = true,
  });

  /// Event `photoMode`; `FRAME_ONLY` is what turns AI off by default.
  final String photoMode;

  /// Event frame catalogue size; zero means framing cannot be a default step.
  final int frameCount;

  /// Kiosk print size token (`s4x6`, `s5x7`, `s6x8`, `s2x6`).
  final String printSize;

  /// Kiosk `printerEnabled`; false makes printing opt-in rather than default.
  final bool printerEnabled;

  bool get aiEnabledDefault => photoMode.trim().toUpperCase() != 'FRAME_ONLY';
  bool get frameEnabledDefault => frameCount > 0;
}

/// Fully resolved pipeline configuration — backend flags, then local override,
/// then [EventPipelineDefaults]. Every field is non-null by construction.
class EventPipelineSettings {
  const EventPipelineSettings({
    required this.pipelineEnabled,
    required this.offlineMode,
    required this.aiEnabled,
    required this.frameEnabled,
    required this.autoPrint,
    required this.defaultCopies,
    required this.printSize,
    required this.qualityFactor,
    required this.mirrorEnabled,
    required this.scanFolders,
    this.themeId,
    this.frameId,
  });

  /// Master switch. Off = every station behaves exactly as it does today.
  final bool pipelineEnabled;

  /// Event-level offline mode. Deliberately **separate** from
  /// `KioskManager.isOperatingModeOffline()`, which is a guest-kiosk policy flag
  /// from a different endpoint. A kiosk in online mode can run an offline event.
  final bool offlineMode;

  final bool aiEnabled;

  /// The single look every AI job uses. There is no per-image theme pick.
  final String? themeId;

  final bool frameEnabled;
  final String? frameId;

  /// Adds [EventPipelineStep.print] to the resolved chain. When false the item
  /// stops after framing and waits for an operator release.
  final bool autoPrint;

  final int defaultCopies;
  final String printSize;

  /// Downscale short-side multiplier over the DNP native width (1920).
  final double qualityFactor;

  /// Best-effort backend mirror. Always false when [offlineMode].
  final bool mirrorEnabled;

  /// Folder prefixes an import scans, e.g. `['DCIM']`.
  final List<String> scanFolders;

  static const List<String> defaultScanFolders = <String>['DCIM'];
  static const double defaultQualityFactor = 1.0;

  /// AI can only run with a theme to run it under.
  bool get canRunAi => aiEnabled && (themeId?.trim().isNotEmpty ?? false);

  /// Framing can only run with a frame to composite.
  bool get canRunFrame => frameEnabled && (frameId?.trim().isNotEmpty ?? false);

  /// The step list frozen onto each item at selection / capture-confirm time.
  ///
  /// Resolved **once** per item and stored, so a settings change mid-event
  /// cannot alter work already in flight. See the workflow spec, §2.2.
  List<String> resolveSteps() {
    return <String>[
      if (canRunAi) EventPipelineStep.ai,
      if (canRunFrame) EventPipelineStep.frame,
      if (autoPrint) EventPipelineStep.print,
    ];
  }

  /// The step list after an operator taps **Skip AI** on stuck items.
  ///
  /// Drops `ai` and keeps whatever the item still has ahead of it. This is the
  /// only sanctioned rewrite of a frozen list, because it is an explicit
  /// operator action rather than settings drift. See spec §4B.2.
  static List<String> withoutAi(Iterable<String> steps) {
    return [
      for (final s in EventPipelineStep.normalize(steps))
        if (s != EventPipelineStep.ai) s,
    ];
  }

  EventPipelineSettings copyWith({
    bool? pipelineEnabled,
    bool? offlineMode,
    bool? aiEnabled,
    String? themeId,
    bool? frameEnabled,
    String? frameId,
    bool? autoPrint,
    int? defaultCopies,
    String? printSize,
    double? qualityFactor,
    bool? mirrorEnabled,
    List<String>? scanFolders,
  }) {
    return EventPipelineSettings(
      pipelineEnabled: pipelineEnabled ?? this.pipelineEnabled,
      offlineMode: offlineMode ?? this.offlineMode,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      themeId: themeId ?? this.themeId,
      frameEnabled: frameEnabled ?? this.frameEnabled,
      frameId: frameId ?? this.frameId,
      autoPrint: autoPrint ?? this.autoPrint,
      defaultCopies: defaultCopies ?? this.defaultCopies,
      printSize: printSize ?? this.printSize,
      qualityFactor: qualityFactor ?? this.qualityFactor,
      mirrorEnabled: mirrorEnabled ?? this.mirrorEnabled,
      scanFolders: scanFolders ?? this.scanFolders,
    );
  }
}
