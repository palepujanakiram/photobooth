class EventInfoModel {
  final String id;
  final String code;
  final String? name;
  final String photoMode;
  final bool currentlyActive;
  final int themeCount;
  final int frameCount;

  const EventInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.photoMode = 'BOTH',
    this.currentlyActive = true,
    this.themeCount = 0,
    this.frameCount = 0,
  });

  factory EventInfoModel.fromJson(Map<String, dynamic> json) {
    final nested = json['event'];
    final src = nested is Map
        ? Map<String, dynamic>.from(nested)
        : json;
    return EventInfoModel(
      id: (src['id'] ?? '').toString(),
      code: (src['code'] ?? '').toString(),
      name: src['name']?.toString(),
      photoMode: (src['photoMode'] ?? src['photo_mode'] ?? 'BOTH').toString(),
      currentlyActive: src['currentlyActive'] != false && src['isActive'] != false,
      themeCount: _asInt(src['themeCount'] ?? src['theme_count']),
      frameCount: _asInt(src['frameCount'] ?? src['frame_count']),
    );
  }

  bool get isValid => id.trim().isNotEmpty && code.trim().isNotEmpty;

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }
}
