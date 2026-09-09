/// **Development scaffold. Delete this file when the TODO below is done.**
///
/// TODO(event-pipeline): remove once `/api/event/by-code/:code` returns
/// `themeId` and `frameId` — see `docs/event-operator-screens-spec.md` §12,
/// "Missing — needed for read-only settings". They are the only two fields
/// without a sane default: `themeIds` and `frameIds` arrive as *lists*, and a
/// list of five frame ids does not tell the device which one to composite.
///
/// Until then an AI or frame event cannot run on real config, so this fills the
/// gap from the catalogue the backend already sends. Picking the first id is
/// exactly the arbitrary guess the spec rejects for production — which is why
/// this is a scaffold with an expiry date and not a setting. There is
/// deliberately no UI for it: settings are sync-only (spec §9), and a device
/// that can be configured by hand is a device that can disagree with ZenAI.
abstract final class EventPipelineDevConfig {
  /// Set false to see exactly how the app behaves once the backend lands: an
  /// event with no `themeId` drops AI from the chain, and one with no `frameId`
  /// drops framing.
  static const bool fillMissingIdsFromCatalogue = true;

  /// Pins a specific id for on-device testing, ahead of the catalogue fallback.
  /// Leave null unless you are chasing one particular theme or frame.
  static const String? themeIdOverride = null;
  static const String? frameIdOverride = null;

  /// The backend value if it sent one, else the pinned id, else the first entry
  /// of the catalogue it did send.
  static String? resolveThemeId({
    String? fromBackend,
    List<String> catalogue = const <String>[],
  }) {
    return _resolve(fromBackend, themeIdOverride, catalogue);
  }

  static String? resolveFrameId({
    String? fromBackend,
    List<String> catalogue = const <String>[],
  }) {
    return _resolve(fromBackend, frameIdOverride, catalogue);
  }

  static String? _resolve(
    String? fromBackend,
    String? pinned,
    List<String> catalogue,
  ) {
    final backend = fromBackend?.trim() ?? '';
    if (backend.isNotEmpty) return backend;

    final override = pinned?.trim() ?? '';
    if (override.isNotEmpty) return override;

    if (!fillMissingIdsFromCatalogue) return null;
    for (final id in catalogue) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
