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
  'noir',
  'polaroid',
  'grid_2x2',
  'filmstrip',
  'romantic',
];

/// Single-sheet layouts (print `s4x6`) vs dual 2×6 chrome (`s6x2_2`).
/// Classic 1-shot 6×4 is a separate compose path (not a look-picker frame).
const List<String> kStripSheetLayoutIds = [
  'polaroid',
  'grid_2x2',
  'romantic',
  'custom_sheet',
];

bool isStripSheetLayout(String frameId) =>
    kStripSheetLayoutIds.contains(frameId);

/// Admin scrapbook templates use catalog ids `st:<uuid>`.
bool isStripTemplateFrame(String frameId) => frameId.startsWith('st:');

const List<String> kStripStickerIds = [
  'none',
  'hearts',
  'sparkles',
  'stars',
  'flowers',
];

/// Sticker types that can be placed (and dragged) on the strip.
const List<String> kPlaceableStripStickerIds = [
  'hearts',
  'sparkles',
  'stars',
  'flowers',
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
    this.kind,
    this.overlayUrl,
    this.caption,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String description;

  /// `template` for admin scrapbook strips; null/builtin otherwise.
  final String? kind;
  final String? overlayUrl;
  final String? caption;
  final String? logoUrl;

  bool get isTemplate => kind == 'template' || isStripTemplateFrame(id);

  factory StripFrame.fromJson(Map<String, dynamic> json) {
    return StripFrame(
      id: JsonParseHelpers.stringValue(json['id']),
      name: JsonParseHelpers.stringValue(json['name']),
      description: JsonParseHelpers.stringValue(json['description']),
      kind: JsonParseHelpers.stringOrNull(json['kind']),
      overlayUrl: JsonParseHelpers.stringOrNull(json['overlayUrl']),
      caption: JsonParseHelpers.stringOrNull(json['caption']),
      logoUrl: JsonParseHelpers.stringOrNull(json['logoUrl']),
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

/// Normalized print geometry from zenai `GET /api/strip/filters` → `layout`.
class StripWysiwygLayout {
  const StripWysiwygLayout({
    required this.borderRatio,
    required this.accentStrokeRatio,
    required this.noirAccentStrokeRatio,
    required this.noirInnerInsetRatio,
    required this.watermarkFontDivisor,
    required this.watermarkFontMin,
    required this.watermarkFontMax,
    required this.watermarkBarHeightFactor,
    required this.stickerBaseRatio,
    required this.stickerLargeRatio,
    required this.stickerMinPx,
    required this.romanticSlots,
    required this.romanticHeartY,
    required this.romanticHeartFont,
    required this.romanticCaptionY,
    required this.romanticCaptionFont,
    required this.romanticCaption,
    required this.polaroidFrameW,
    required this.polaroidFrameH,
    required this.polaroidSlots,
    required this.gridHeaderH,
    required this.gridFooterH,
    required this.gridMargin,
    required this.gridGap,
    required this.gridTitle,
    required this.gridSubtitle,
    required this.filmRailW,
    required this.filmMarginY,
    required this.filmGutter,
    required this.filmStripPadX,
    required this.filmHoleW,
    required this.filmHoleH,
    required this.filmHolePitch,
    required this.filmCellAspect,
    required this.filmLabel,
  });

  final double borderRatio;
  final double accentStrokeRatio;
  final double noirAccentStrokeRatio;
  final double noirInnerInsetRatio;
  final double watermarkFontDivisor;
  final double watermarkFontMin;
  final double watermarkFontMax;
  final double watermarkBarHeightFactor;
  final double stickerBaseRatio;
  final double stickerLargeRatio;
  final double stickerMinPx;
  final List<({double left, double top, double width, double height})>
      romanticSlots;
  final double romanticHeartY;
  final double romanticHeartFont;
  final double romanticCaptionY;
  final double romanticCaptionFont;
  final String romanticCaption;
  final double polaroidFrameW;
  final double polaroidFrameH;
  final List<({double left, double top, double rotDeg})> polaroidSlots;
  final double gridHeaderH;
  final double gridFooterH;
  final double gridMargin;
  final double gridGap;
  final String gridTitle;
  final String gridSubtitle;
  final double filmRailW;
  final double filmMarginY;
  final double filmGutter;
  final double filmStripPadX;
  final double filmHoleW;
  final double filmHoleH;
  final double filmHolePitch;
  final double filmCellAspect;
  final String filmLabel;

  /// Matches zenai `STRIP_WYSIWYG_LAYOUT` when the API omits `layout`.
  static const StripWysiwygLayout defaults = StripWysiwygLayout(
    borderRatio: 4 / 600,
    accentStrokeRatio: 1.75 / 600,
    noirAccentStrokeRatio: 2.5 / 600,
    noirInnerInsetRatio: 5 / 600,
    watermarkFontDivisor: 48,
    watermarkFontMin: 8,
    watermarkFontMax: 12,
    watermarkBarHeightFactor: 1.85,
    stickerBaseRatio: 0.16,
    stickerLargeRatio: 0.2,
    stickerMinPx: 14,
    romanticSlots: [
      (left: 70 / 1200, top: 110 / 1800, width: 520 / 1200, height: 640 / 1800),
      (left: 610 / 1200, top: 160 / 1800, width: 520 / 1200, height: 640 / 1800),
      (left: 120 / 1200, top: 780 / 1800, width: 360 / 1200, height: 440 / 1800),
      (left: 700 / 1200, top: 860 / 1800, width: 360 / 1200, height: 440 / 1800),
    ],
    romanticHeartY: 78 / 1800,
    romanticHeartFont: 64 / 1200,
    romanticCaptionY: 1670 / 1800,
    romanticCaptionFont: 36 / 1200,
    romanticCaption: 'Forever starts here',
    polaroidFrameW: 464 / 1200,
    polaroidFrameH: 612 / 1800,
    polaroidSlots: [
      (left: 70 / 1200, top: 90 / 1800, rotDeg: -4),
      (left: 620 / 1200, top: 70 / 1800, rotDeg: 3),
      (left: 90 / 1200, top: 920 / 1800, rotDeg: 2.5),
      (left: 600 / 1200, top: 900 / 1800, rotDeg: -3),
    ],
    gridHeaderH: 160 / 1800,
    gridFooterH: 90 / 1800,
    gridMargin: 48 / 1200,
    gridGap: 28 / 1200,
    gridTitle: 'Together',
    gridSubtitle: 'Our favorite moments',
    // Sheet-normalized (1200-wide); dual-strip chrome uses StripChromeLook ratios.
    filmRailW: 52 / 1200,
    filmMarginY: 72 / 1800,
    filmGutter: 14 / 1800,
    filmStripPadX: 150 / 1200,
    filmHoleW: 26 / 1200,
    filmHoleH: 34 / 1800,
    filmHolePitch: 58 / 1800,
    filmCellAspect: 496 / 448,
    filmLabel: 'MEMORIES',
  );

  factory StripWysiwygLayout.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final strip = _asMap(json['strip']);
    final wm = _asMap(json['watermark']);
    final stickers = _asMap(json['stickers']);
    final romantic = _asMap(json['romantic']);
    final polaroid = _asMap(json['polaroid']);
    final grid = _asMap(json['grid2x2']);
    final film = _asMap(json['filmstrip']);
    return StripWysiwygLayout(
      borderRatio: _d(strip?['borderRatio'], defaults.borderRatio),
      accentStrokeRatio:
          _d(strip?['accentStrokeRatio'], defaults.accentStrokeRatio),
      noirAccentStrokeRatio:
          _d(strip?['noirAccentStrokeRatio'], defaults.noirAccentStrokeRatio),
      noirInnerInsetRatio:
          _d(strip?['noirInnerInsetRatio'], defaults.noirInnerInsetRatio),
      watermarkFontDivisor:
          _d(wm?['fontDivisor'], defaults.watermarkFontDivisor),
      watermarkFontMin: _d(wm?['fontMin'], defaults.watermarkFontMin),
      watermarkFontMax: _d(wm?['fontMax'], defaults.watermarkFontMax),
      watermarkBarHeightFactor:
          _d(wm?['barHeightFactor'], defaults.watermarkBarHeightFactor),
      stickerBaseRatio: _d(stickers?['baseRatio'], defaults.stickerBaseRatio),
      stickerLargeRatio: _d(stickers?['largeRatio'], defaults.stickerLargeRatio),
      stickerMinPx: _d(stickers?['minPx'], defaults.stickerMinPx),
      romanticSlots: _parseRomanticSlots(romantic?['slots']),
      romanticHeartY: _d(romantic?['heartY'], defaults.romanticHeartY),
      romanticHeartFont: _d(romantic?['heartFont'], defaults.romanticHeartFont),
      romanticCaptionY: _d(romantic?['captionY'], defaults.romanticCaptionY),
      romanticCaptionFont:
          _d(romantic?['captionFont'], defaults.romanticCaptionFont),
      romanticCaption: JsonParseHelpers.stringValue(
        romantic?['caption'],
        fallback: defaults.romanticCaption,
      ),
      polaroidFrameW: _d(polaroid?['frameW'], defaults.polaroidFrameW),
      polaroidFrameH: _d(polaroid?['frameH'], defaults.polaroidFrameH),
      polaroidSlots: _parsePolaroidSlots(polaroid?['slots']),
      gridHeaderH: _d(grid?['headerH'], defaults.gridHeaderH),
      gridFooterH: _d(grid?['footerH'], defaults.gridFooterH),
      gridMargin: _d(grid?['margin'], defaults.gridMargin),
      gridGap: _d(grid?['gap'], defaults.gridGap),
      gridTitle: JsonParseHelpers.stringValue(
        grid?['title'],
        fallback: defaults.gridTitle,
      ),
      gridSubtitle: JsonParseHelpers.stringValue(
        grid?['subtitle'],
        fallback: defaults.gridSubtitle,
      ),
      filmRailW: _d(film?['railW'], defaults.filmRailW),
      filmMarginY: _d(film?['marginY'], defaults.filmMarginY),
      filmGutter: _d(film?['gutter'], defaults.filmGutter),
      filmStripPadX: _d(film?['stripPadX'], defaults.filmStripPadX),
      filmHoleW: _d(film?['holeW'], defaults.filmHoleW),
      filmHoleH: _d(film?['holeH'], defaults.filmHoleH),
      filmHolePitch: _d(film?['holePitch'], defaults.filmHolePitch),
      filmCellAspect: _d(film?['cellAspect'], defaults.filmCellAspect),
      filmLabel: JsonParseHelpers.stringValue(
        film?['label'],
        fallback: defaults.filmLabel,
      ),
    );
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static double _d(Object? raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return fallback;
  }

  static List<({double left, double top, double width, double height})>
      _parseRomanticSlots(Object? raw) {
    if (raw is! List || raw.length != 4) return defaults.romanticSlots;
    final out =
        <({double left, double top, double width, double height})>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) return defaults.romanticSlots;
      out.add((
        left: _d(m['left'], 0),
        top: _d(m['top'], 0),
        width: _d(m['width'], 0),
        height: _d(m['height'], 0),
      ));
    }
    return out;
  }

  static List<({double left, double top, double rotDeg})> _parsePolaroidSlots(
    Object? raw,
  ) {
    if (raw is! List || raw.length != 4) return defaults.polaroidSlots;
    final out = <({double left, double top, double rotDeg})>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) return defaults.polaroidSlots;
      out.add((
        left: _d(m['left'], 0),
        top: _d(m['top'], 0),
        rotDeg: _d(m['rotDeg'], 0),
      ));
    }
    return out;
  }
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
    this.layout,
    this.enableSurpriseMeAi = false,
    this.enableOsdScrub = false,
  });

  final String brand;
  final int shotCount;
  final List<StripFilter> filters;
  final List<StripFrame> frames;
  final List<StripSticker> stickers;
  final String printSize;
  final int copiesOnSheet;
  final String? printNote;
  final StripWysiwygLayout? layout;
  final bool enableSurpriseMeAi;
  /// Master Classic cleanup switch from admin (`features.enableOsdScrub`).
  final bool enableOsdScrub;

  StripWysiwygLayout get wysiwyg => layout ?? StripWysiwygLayout.defaults;

  factory StripFiltersCatalog.fromJson(Map<String, dynamic> json) {
    final print = json['print'];
    Map<String, dynamic>? printMap;
    if (print is Map<String, dynamic>) {
      printMap = print;
    } else if (print is Map) {
      printMap = Map<String, dynamic>.from(print);
    }
    final layoutRaw = json['layout'];
    Map<String, dynamic>? layoutMap;
    if (layoutRaw is Map<String, dynamic>) {
      layoutMap = layoutRaw;
    } else if (layoutRaw is Map) {
      layoutMap = Map<String, dynamic>.from(layoutRaw);
    }
    final featuresRaw = json['features'];
    Map<String, dynamic>? featuresMap;
    if (featuresRaw is Map<String, dynamic>) {
      featuresMap = featuresRaw;
    } else if (featuresRaw is Map) {
      featuresMap = Map<String, dynamic>.from(featuresRaw);
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
      layout: StripWysiwygLayout.fromJson(layoutMap),
      enableSurpriseMeAi:
          JsonParseHelpers.boolOrNull(featuresMap?['enableSurpriseMeAi']) ??
              false,
      enableOsdScrub:
          JsonParseHelpers.boolOrNull(featuresMap?['enableOsdScrub']) ?? false,
    );
  }
}

/// Status from `GET /api/sessions/:id/surprise-me`.
class SurpriseMeStatus {
  const SurpriseMeStatus({
    required this.status,
    required this.showUpsell,
    this.imageUrl,
    this.qualityScore,
    this.qualityThreshold,
    this.themeId,
    this.themeName,
  });

  final String status;
  final bool showUpsell;
  final String? imageUrl;
  final int? qualityScore;
  final int? qualityThreshold;
  final String? themeId;
  final String? themeName;

  factory SurpriseMeStatus.fromJson(Map<String, dynamic> json) {
    return SurpriseMeStatus(
      status: JsonParseHelpers.stringValue(json['status'], fallback: 'idle'),
      showUpsell: JsonParseHelpers.boolOrNull(json['showUpsell']) ?? false,
      imageUrl: JsonParseHelpers.stringOrNull(json['imageUrl']),
      qualityScore: JsonParseHelpers.intOrNull(json['qualityScore']),
      qualityThreshold: JsonParseHelpers.intOrNull(json['qualityThreshold']),
      themeId: JsonParseHelpers.stringOrNull(json['themeId']),
      themeName: JsonParseHelpers.stringOrNull(json['themeName']),
    );
  }
}

/// Result of `POST /api/sessions/:id/strip/clean-overlays`.
class StripOverlayCleanResult {
  const StripOverlayCleanResult({
    required this.images,
    required this.cleanedFlags,
    this.skipped = false,
  });

  final List<String> images;

  /// Per-shot cleanup success from the server (Gemini / local AF scrub).
  final List<bool> cleanedFlags;

  /// Admin scrub OFF / kill-switch — images are unchanged inputs.
  final bool skipped;

  bool get allCleaned =>
      !skipped &&
      cleanedFlags.length == images.length &&
      cleanedFlags.isNotEmpty &&
      cleanedFlags.every((c) => c);
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
    this.runId,
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

  /// Transformation run id for forensics / View details (`GET /api/generation-runs/:id`).
  final String? runId;

  /// URL to download for printing — dual-strip uses composite; 1-shot 6×4 uses [imageUrl].
  String get printImageUrl {
    if (_usesSingleSheetPrint) {
      return _primaryImageUrl;
    }
    final composite = stripCompositeUrl?.trim() ?? '';
    if (composite.isNotEmpty) return composite;
    return _primaryImageUrl;
  }

  bool get _usesSingleSheetPrint {
    final size = printSize.trim().toLowerCase();
    if (size == AppConstants.kPrintSizeLandscape6x4 ||
        size == AppConstants.kPrintSizePortrait4x6) {
      return true;
    }
    if (copiesOnSheet <= 1) return true;
    final w = width;
    final h = height;
    if (w != null && h != null && w > h) return true;
    return false;
  }

  String get _primaryImageUrl {
    final direct = imageUrl.trim();
    if (direct.isNotEmpty) return direct;
    return stripCompositeUrl?.trim() ?? '';
  }

  factory StripComposeResult.fromJson(
    Map<String, dynamic> json, {
    int? composeImageCount,
  }) {
    final rawImage = JsonParseHelpers.stringOrNull(json['imageUrl']);
    final rawComposite = JsonParseHelpers.stringOrNull(json['stripCompositeUrl']);
    final imageUrl = composeImageCount == 1
        ? (rawImage ?? '')
        : (rawImage ?? rawComposite ?? '');
    final apiPrintSize = JsonParseHelpers.stringOrNull(json['printSize']);
    final printSize = composeImageCount != null
        ? _resolveComposePrintSize(
            composeImageCount: composeImageCount,
            apiPrintSize: apiPrintSize,
          )
        : JsonParseHelpers.stringValue(
            json['printSize'],
            fallback: AppConstants.kPrintSizeStripDual2x6,
          );
    final copiesOnSheet = composeImageCount == 1
        ? 1
        : (JsonParseHelpers.intOrNull(json['copiesOnSheet']) ?? 2);
    return StripComposeResult(
      imageUrl: imageUrl,
      stripCompositeUrl: rawComposite,
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
      copiesOnSheet: copiesOnSheet,
      printSize: printSize,
      runId: JsonParseHelpers.stringOrNull(json['runId']) ??
          JsonParseHelpers.stringOrNull(json['run_id']),
    );
  }

  static String _resolveComposePrintSize({
    required int composeImageCount,
    String? apiPrintSize,
  }) {
    final fromApi = apiPrintSize?.trim() ?? '';
    if (composeImageCount == 1) {
      if (fromApi == AppConstants.kPrintSizePortrait4x6 ||
          fromApi == AppConstants.kPrintSizeLandscape6x4) {
        return fromApi;
      }
      // Legacy servers omitted printSize for 1-shot (always landscape 6×4).
      return AppConstants.kPrintSizeLandscape6x4;
    }
    if (fromApi.isNotEmpty) return fromApi;
    return AppConstants.kPrintSizeStripDual2x6;
  }
}
