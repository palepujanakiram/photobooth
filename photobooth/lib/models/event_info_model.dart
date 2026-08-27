class EventInfoModel {
  final String id;
  final String code;
  final String? name;
  final String photoMode;
  final bool currentlyActive;
  final int themeCount;
  final int frameCount;
  final List<String> themeIds;
  final List<String> frameIds;

  const EventInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.photoMode = 'BOTH',
    this.currentlyActive = true,
    this.themeCount = 0,
    this.frameCount = 0,
    this.themeIds = const [],
    this.frameIds = const [],
  });

  factory EventInfoModel.fromJson(Map<String, dynamic> json) {
    final nested = json['event'];
    final src = nested is Map ? Map<String, dynamic>.from(nested) : json;
    return EventInfoModel(
      id: (src['id'] ?? '').toString(),
      code: (src['code'] ?? '').toString(),
      name: src['name']?.toString(),
      photoMode: (src['photoMode'] ?? src['photo_mode'] ?? 'BOTH').toString(),
      currentlyActive:
          src['currentlyActive'] != false && src['isActive'] != false,
      themeCount: _asInt(src['themeCount'] ?? src['theme_count']),
      frameCount: _asInt(src['frameCount'] ?? src['frame_count']),
      themeIds: _stringList(src['themeIds'] ?? src['theme_ids']),
      frameIds: _stringList(src['frameIds'] ?? src['frame_ids']),
    );
  }

  bool get isValid => id.trim().isNotEmpty && code.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        if (name != null) 'name': name,
        'photoMode': photoMode,
        'currentlyActive': currentlyActive,
        'themeCount': themeCount,
        'frameCount': frameCount,
        'themeIds': themeIds,
        'frameIds': frameIds,
      };

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
