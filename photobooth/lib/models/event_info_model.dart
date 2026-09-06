class EventInfoCatalog {
  final int themeCount;
  final int frameCount;
  final List<String> themeIds;
  final List<String> frameIds;

  const EventInfoCatalog({
    this.themeCount = 0,
    this.frameCount = 0,
    this.themeIds = const [],
    this.frameIds = const [],
  });
}

class EventSkinChrome {
  final String id;
  final String name;
  final String bannerFrom;
  final String bannerTo;
  final String ink;

  const EventSkinChrome({
    this.id = 'wedding-gold',
    this.name = 'Wedding gold',
    this.bannerFrom = '#E3A65C',
    this.bannerTo = '#6E5391',
    this.ink = '#FFFFFF',
  });

  factory EventSkinChrome.fromJson(Map<String, dynamic> json) {
    return EventSkinChrome(
      id: _nonEmpty(json['id'], 'wedding-gold'),
      name: _nonEmpty(json['name'], 'Wedding gold'),
      bannerFrom: _hex(json['bannerFrom'] ?? json['banner_from'], '#E3A65C'),
      bannerTo: _hex(json['bannerTo'] ?? json['banner_to'], '#6E5391'),
      ink: _hex(json['ink'], '#FFFFFF'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bannerFrom': bannerFrom,
        'bannerTo': bannerTo,
        'ink': ink,
      };
}

class EventChrome {
  final String outputMode;
  final EventSkinChrome skin;

  const EventChrome({
    this.outputMode = 'BOTH',
    this.skin = const EventSkinChrome(),
  });

  factory EventChrome.fromJson(Map<String, dynamic> json) {
    final skinRaw = json['skin'];
    return EventChrome(
      outputMode: _outputMode(json['outputMode'] ?? json['output_mode']),
      skin: skinRaw is Map
          ? EventSkinChrome.fromJson(Map<String, dynamic>.from(skinRaw))
          : const EventSkinChrome(),
    );
  }

  Map<String, dynamic> toJson() => {
        'outputMode': outputMode,
        'skin': skin.toJson(),
      };
}

class EventInfoModel {
  final String id;
  final String code;
  final String? name;
  final String photoMode;
  final bool currentlyActive;
  final EventInfoCatalog catalog;
  final EventChrome chrome;

  const EventInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.photoMode = 'BOTH',
    this.currentlyActive = true,
    this.catalog = const EventInfoCatalog(),
    this.chrome = const EventChrome(),
  });

  int get themeCount => catalog.themeCount;
  int get frameCount => catalog.frameCount;
  List<String> get themeIds => catalog.themeIds;
  List<String> get frameIds => catalog.frameIds;
  String get outputMode => chrome.outputMode;

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
      catalog: EventInfoCatalog(
        themeCount: _asInt(src['themeCount'] ?? src['theme_count']),
        frameCount: _asInt(src['frameCount'] ?? src['frame_count']),
        themeIds: _stringList(src['themeIds'] ?? src['theme_ids']),
        frameIds: _stringList(src['frameIds'] ?? src['frame_ids']),
      ),
      chrome: EventChrome.fromJson(src),
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
        ...chrome.toJson(),
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

int? parseRgbHex(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  return int.tryParse(h, radix: 16);
}

String _nonEmpty(dynamic raw, String fallback) {
  final v = (raw ?? '').toString().trim();
  return v.isEmpty ? fallback : v;
}

String _hex(dynamic raw, String fallback) {
  final v = (raw ?? '').toString().trim();
  if (v.isEmpty) return fallback;
  return v.startsWith('#') ? v : '#$v';
}

String _outputMode(dynamic raw) {
  final v = (raw ?? '').toString();
  if (v == 'PHYSICAL_PRINT' || v == 'DIGITAL_ONLY' || v == 'BOTH') return v;
  return 'BOTH';
}
