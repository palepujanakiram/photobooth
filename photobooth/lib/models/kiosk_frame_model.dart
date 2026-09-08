import 'strip_models.dart';

/// 6×2 occasion overlays that share kiosk assignment with the 4×6 AI PNG.
class KioskFrameStripAssets {
  const KioskFrameStripAssets({
    this.overlayUrl = '',
    this.overlay3Url = '',
    this.slots = const [],
    this.slots3 = const [],
  });

  /// 4-shot 6×2 PNG (`fr:<id>`).
  final String overlayUrl;

  /// 3-shot 6×2 PNG (`f3:<id>`).
  final String overlay3Url;
  final List<StripTemplateSlot> slots;
  final List<StripTemplateSlot> slots3;

  bool get has4 => overlayUrl.trim().isNotEmpty;
  bool get has3 => overlay3Url.trim().isNotEmpty;
}

/// Occasion frame returned by `GET /api/kiosk/frames` for kiosk flow.
class KioskFrameModel {
  final String id;
  final String name;
  final String overlayUrl;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final KioskFrameStripAssets strip;

  const KioskFrameModel({
    required this.id,
    required this.name,
    required this.overlayUrl,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.strip = const KioskFrameStripAssets(),
  });

  factory KioskFrameModel.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final nameRaw = json['name'];
    final urlRaw = json['overlayUrl'];
    return KioskFrameModel(
      id: idRaw == null ? '' : idRaw.toString(),
      name: nameRaw == null ? '' : nameRaw.toString(),
      overlayUrl: urlRaw == null ? '' : urlRaw.toString(),
      scheduledStartAt: _parseDate(json['scheduledStartAt']),
      scheduledEndAt: _parseDate(json['scheduledEndAt']),
      strip: KioskFrameStripAssets(
        overlayUrl: json['stripOverlayUrl']?.toString() ?? '',
        overlay3Url: json['strip3OverlayUrl']?.toString() ?? '',
        slots: parseStripTemplateSlots(json['stripSlots']),
        slots3: parseStripTemplateSlots(json['strip3Slots']),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'overlayUrl': overlayUrl,
        if (scheduledStartAt != null)
          'scheduledStartAt': scheduledStartAt!.toIso8601String(),
        if (scheduledEndAt != null)
          'scheduledEndAt': scheduledEndAt!.toIso8601String(),
        if (strip.overlayUrl.isNotEmpty) 'stripOverlayUrl': strip.overlayUrl,
        if (strip.overlay3Url.isNotEmpty)
          'strip3OverlayUrl': strip.overlay3Url,
        if (strip.slots.isNotEmpty)
          'stripSlots': strip.slots.map((s) => s.toJson()).toList(),
        if (strip.slots3.isNotEmpty)
          'strip3Slots': strip.slots3.map((s) => s.toJson()).toList(),
      };

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
