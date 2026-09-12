import '../../utils/json_parse_helpers.dart';

/// Event pipeline flags as returned by `/api/event/by-code/:code`.
///
/// Every field is nullable: **null means the backend did not send it**, which is
/// different from the backend sending `false`. Null defers to
/// [EventPipelineDefaults]; `false` is an explicit backend decision.
///
/// Parsed by a standalone reader rather than extending `EventInfoModel`, so the
/// existing guest-flow model is untouched by the pipeline work.
class EventPipelineFlags {
  const EventPipelineFlags({
    this.pipelineEnabled,
    this.offlineMode,
    this.aiEnabled,
    this.themeId,
    this.frameEnabled,
    this.frameId,
    this.autoPrint,
    this.defaultCopies,
    this.printSize,
    this.mirrorEnabled,
  });

  final bool? pipelineEnabled;
  final bool? offlineMode;
  final bool? aiEnabled;
  final String? themeId;
  final bool? frameEnabled;
  final String? frameId;
  final bool? autoPrint;
  final int? defaultCopies;
  final String? printSize;
  final bool? mirrorEnabled;

  static const empty = EventPipelineFlags();

  /// Reads pipeline flags from an `/api/event/by-code` body.
  ///
  /// Accepts the same shapes `EventInfoModel.fromJson` does — a nested `event`
  /// object, and snake_case alongside camelCase — because the two parse the same
  /// payload and a caller should not have to care which key style the API used.
  factory EventPipelineFlags.fromEventJson(Map<String, dynamic> json) {
    final nested = json['event'];
    final root = nested is Map ? Map<String, dynamic>.from(nested) : json;
    final scoped = root['pipeline'];
    final src = scoped is Map
        ? <String, dynamic>{...root, ...Map<String, dynamic>.from(scoped)}
        : root;

    return EventPipelineFlags(
      pipelineEnabled: _bool(src, 'pipelineEnabled', 'pipeline_enabled'),
      offlineMode: _bool(src, 'offlineMode', 'offline_mode'),
      aiEnabled: _bool(src, 'aiEnabled', 'ai_enabled'),
      themeId: _string(src, 'themeId', 'theme_id'),
      frameEnabled: _bool(src, 'frameEnabled', 'frame_enabled'),
      frameId: _string(src, 'frameId', 'frame_id'),
      autoPrint: _bool(src, 'autoPrint', 'auto_print'),
      defaultCopies: _copies(src),
      printSize: _string(src, 'printSize', 'print_size'),
      mirrorEnabled: _bool(src, 'mirrorEnabled', 'mirror_enabled'),
    );
  }

  bool get isEmpty =>
      pipelineEnabled == null &&
      offlineMode == null &&
      aiEnabled == null &&
      themeId == null &&
      frameEnabled == null &&
      frameId == null &&
      autoPrint == null &&
      defaultCopies == null &&
      printSize == null &&
      mirrorEnabled == null;

  EventPipelineFlags copyWith({
    bool? pipelineEnabled,
    bool? offlineMode,
    bool? aiEnabled,
    String? themeId,
    bool? frameEnabled,
    String? frameId,
    bool? autoPrint,
    int? defaultCopies,
    String? printSize,
    bool? mirrorEnabled,
  }) {
    return EventPipelineFlags(
      pipelineEnabled: pipelineEnabled ?? this.pipelineEnabled,
      offlineMode: offlineMode ?? this.offlineMode,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      themeId: themeId ?? this.themeId,
      frameEnabled: frameEnabled ?? this.frameEnabled,
      frameId: frameId ?? this.frameId,
      autoPrint: autoPrint ?? this.autoPrint,
      defaultCopies: defaultCopies ?? this.defaultCopies,
      printSize: printSize ?? this.printSize,
      mirrorEnabled: mirrorEnabled ?? this.mirrorEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (pipelineEnabled != null) 'pipelineEnabled': pipelineEnabled,
        if (offlineMode != null) 'offlineMode': offlineMode,
        if (aiEnabled != null) 'aiEnabled': aiEnabled,
        if (themeId != null) 'themeId': themeId,
        if (frameEnabled != null) 'frameEnabled': frameEnabled,
        if (frameId != null) 'frameId': frameId,
        if (autoPrint != null) 'autoPrint': autoPrint,
        if (defaultCopies != null) 'defaultCopies': defaultCopies,
        if (printSize != null) 'printSize': printSize,
        if (mirrorEnabled != null) 'mirrorEnabled': mirrorEnabled,
      };

  static bool? _bool(Map<String, dynamic> src, String camel, String snake) {
    return JsonParseHelpers.boolOrNull(src[camel] ?? src[snake]);
  }

  static String? _string(Map<String, dynamic> src, String camel, String snake) {
    final v = JsonParseHelpers.stringOrNull(src[camel] ?? src[snake]);
    final trimmed = v?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Copies below 1 are meaningless; a backend 0 is treated as "unset" rather
  /// than silently queueing prints that produce nothing.
  static int? _copies(Map<String, dynamic> src) {
    final raw = JsonParseHelpers.intOrNull(
      src['defaultCopies'] ?? src['default_copies'],
    );
    if (raw == null || raw < 1) return null;
    return raw;
  }
}
