/// Occasion frame returned by `GET /api/kiosk/frames` for kiosk flow.
class KioskFrameModel {
  final String id;
  final String name;
  final String overlayUrl;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;

  const KioskFrameModel({
    required this.id,
    required this.name,
    required this.overlayUrl,
    this.scheduledStartAt,
    this.scheduledEndAt,
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
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
