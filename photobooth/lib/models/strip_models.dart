import '../utils/json_parse_helpers.dart';
import '../utils/constants.dart';

/// Default FotoFlashback look when the API omits / invalidates [filter].
const String kDefaultStripFilterId = 'classic_warm';

/// Default frame chrome when the API omits / invalidates [frame].
const String kDefaultStripFrameId = 'classic';

/// Default sticker pack when the API omits / invalidates [sticker].
const String kDefaultStripStickerId = 'none';

/// Exact shot count required by `POST /api/sessions/:id/strip/compose`.
const int kStripShotCount = 4;

/// Catalog order from zenai `STRIP_FILTER_IDS` / `GET /api/strip/filters`.
const List<String> kStripFilterIds = [
  'classic_warm',
  'peach_glow',
  'soft_film',
  'candy_pop',
  'golden_hour',
  'cool_mint',
  'gloss_pop',
  'mono',
  'clean',
];

const List<String> kStripFrameIds = [
  'classic',
  'ticket',
  'blush',
  'noir',
];

const List<String> kStripStickerIds = [
  'none',
  'hearts',
  'sparkles',
  'confetti',
  'stars',
  'bows',
  'flowers',
  'butterflies',
  'petals',
];

/// Sticker types that can be placed (and dragged) on the strip.
const List<String> kPlaceableStripStickerIds = [
  'hearts',
  'sparkles',
  'confetti',
  'stars',
  'bows',
  'flowers',
  'butterflies',
  'petals',
];

/// Soft cap so guests don't cover the whole strip.
const int kMaxStripStickerPlacements = 16;

/// Soft cap for freehand personalization strokes.
const int kMaxStripScribbleStrokes = 48;

/// Max points kept per stroke (extra points are skipped while drawing).
const int kMaxStripScribblePoints = 120;

/// Booth scribble pen colors (hex #RRGGBB).
const List<String> kStripScribblePenColors = [
  '#FFFFFF',
  '#111111',
  '#FF4D6D',
  '#FFB703',
  '#4CC9F0',
];

/// One freehand stroke in normalized strip space (0–1).
class StripScribbleStroke {
  const StripScribbleStroke({
    required this.color,
    required this.width,
    required this.points,
  });

  /// Hex color `#RRGGBB`.
  final String color;

  /// Stroke width as a fraction of strip width (e.g. 0.02).
  final double width;

  final List<StripScribblePoint> points;

  Map<String, dynamic> toJson() => {
        'color': color,
        'width': width,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

class StripScribblePoint {
  const StripScribblePoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

/// One sticker instance on the strip (normalized coords, origin top-left).
class StripStickerPlacement {
  const StripStickerPlacement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.scale = 1,
  });

  final String id;

  /// One of [kPlaceableStripStickerIds].
  final String type;

  /// Horizontal center in 0–1 strip space.
  final double x;

  /// Vertical center in 0–1 strip space.
  final double y;

  final double scale;

  StripStickerPlacement copyWith({
    double? x,
    double? y,
    double? scale,
  }) {
    return StripStickerPlacement(
      id: id,
      type: type,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'x': x,
        'y': y,
        'scale': scale,
      };
}

/// Per-frame print cell aspect (width ÷ height) for a 2×6 strip.
///
/// Matches zenai `stripCompositor` cellGeometry at 300 DPI:
/// strip 600×1800, border 4, gutter 0 → cell 592×448 (landscape).
/// Shots are cover-cropped edge-to-edge (no blur/letterbox fill).
const double kStripCellAspectRatio = 592 / 448;

/// One look from `GET /api/strip/filters`.
class StripFilter {
  const StripFilter({
    required this.id,
    required this.name,
    required this.description,
    required this.cssFilter,
  });

  final String id;
  final String name;
  final String description;

  /// CSS `filter` hint for web preview; Flutter uses [id] for approximations.
  final String cssFilter;

  factory StripFilter.fromJson(Map<String, dynamic> json) {
    return StripFilter(
      id: JsonParseHelpers.stringValue(json['id']),
      name: JsonParseHelpers.stringValue(json['name']),
      description: JsonParseHelpers.stringValue(json['description']),
      cssFilter:
          JsonParseHelpers.stringValue(json['cssFilter'], fallback: 'none'),
    );
  }
}

/// Frame chrome option from `GET /api/strip/filters`.
class StripFrame {
  const StripFrame({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  factory StripFrame.fromJson(Map<String, dynamic> json) {
    return StripFrame(
      id: JsonParseHelpers.stringValue(json['id']),
      name: JsonParseHelpers.stringValue(json['name']),
      description: JsonParseHelpers.stringValue(json['description']),
    );
  }
}

/// Sticker pack option from `GET /api/strip/filters`.
class StripSticker {
  const StripSticker({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  factory StripSticker.fromJson(Map<String, dynamic> json) {
    return StripSticker(
      id: JsonParseHelpers.stringValue(json['id']),
      name: JsonParseHelpers.stringValue(json['name']),
      description: JsonParseHelpers.stringValue(json['description']),
    );
  }
}

List<T> _parseNamedList<T>(
  dynamic raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  final out = <T>[];
  if (raw is! List) return out;
  for (final item in raw) {
    if (item is Map<String, dynamic>) {
      out.add(fromJson(item));
    } else if (item is Map) {
      out.add(fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return out;
}

/// Catalog payload from `GET /api/strip/filters`.
class StripFiltersCatalog {
  const StripFiltersCatalog({
    required this.brand,
    required this.shotCount,
    required this.filters,
    this.frames = const [],
    this.stickers = const [],
    this.printSize = AppConstants.kPrintSizeStripDual2x6,
    this.copiesOnSheet = 2,
    this.printNote,
  });

  final String brand;
  final int shotCount;
  final List<StripFilter> filters;
  final List<StripFrame> frames;
  final List<StripSticker> stickers;
  final String printSize;
  final int copiesOnSheet;
  final String? printNote;

  factory StripFiltersCatalog.fromJson(Map<String, dynamic> json) {
    final print = json['print'];
    Map<String, dynamic>? printMap;
    if (print is Map<String, dynamic>) {
      printMap = print;
    } else if (print is Map) {
      printMap = Map<String, dynamic>.from(print);
    }
    return StripFiltersCatalog(
      brand: JsonParseHelpers.stringValue(
        json['brand'],
        fallback: 'FotoFlashback',
      ),
      shotCount: JsonParseHelpers.intOrNull(json['shotCount']) ?? kStripShotCount,
      filters: _parseNamedList(json['filters'], StripFilter.fromJson),
      frames: _parseNamedList(json['frames'], StripFrame.fromJson),
      stickers: _parseNamedList(json['stickers'], StripSticker.fromJson),
      printSize: JsonParseHelpers.stringValue(
        printMap?['size'],
        fallback: AppConstants.kPrintSizeStripDual2x6,
      ),
      copiesOnSheet: JsonParseHelpers.intOrNull(printMap?['copiesOnSheet']) ?? 2,
      printNote: JsonParseHelpers.stringOrNull(printMap?['note']),
    );
  }
}

/// Result of `POST /api/sessions/:id/strip/compose`.
class StripComposeResult {
  const StripComposeResult({
    required this.imageUrl,
    required this.filter,
    this.frame = kDefaultStripFrameId,
    this.sticker = kDefaultStripStickerId,
    this.stripCompositeUrl,
    this.width,
    this.height,
    this.copiesOnSheet = 2,
    this.printSize = AppConstants.kPrintSizeStripDual2x6,
  });

  final String imageUrl;
  final String filter;
  final String frame;
  final String sticker;

  /// Dual 2×6-on-4×6 sheet (print payload for one `s4x6` → two strips).
  final String? stripCompositeUrl;
  final int? width;
  final int? height;
  final int copiesOnSheet;
  final String printSize;

  /// Prefer composite URL when present (same sheet as print).
  String get printImageUrl {
    final composite = stripCompositeUrl?.trim() ?? '';
    if (composite.isNotEmpty) return composite;
    return imageUrl;
  }

  factory StripComposeResult.fromJson(Map<String, dynamic> json) {
    final imageUrl = JsonParseHelpers.stringOrNull(json['imageUrl']) ??
        JsonParseHelpers.stringOrNull(json['stripCompositeUrl']) ??
        '';
    return StripComposeResult(
      imageUrl: imageUrl,
      stripCompositeUrl:
          JsonParseHelpers.stringOrNull(json['stripCompositeUrl']),
      filter: JsonParseHelpers.stringValue(
        json['filter'],
        fallback: kDefaultStripFilterId,
      ),
      frame: JsonParseHelpers.stringValue(
        json['frame'],
        fallback: kDefaultStripFrameId,
      ),
      sticker: JsonParseHelpers.stringValue(
        json['sticker'],
        fallback: kDefaultStripStickerId,
      ),
      width: JsonParseHelpers.intOrNull(json['width']),
      height: JsonParseHelpers.intOrNull(json['height']),
      copiesOnSheet: JsonParseHelpers.intOrNull(json['copiesOnSheet']) ?? 2,
      printSize: JsonParseHelpers.stringValue(
        json['printSize'],
        fallback: AppConstants.kPrintSizeStripDual2x6,
      ),
    );
  }
}
