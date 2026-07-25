import '../utils/json_parse_helpers.dart';
import '../utils/constants.dart';

/// Default FotoFlashback look when the API omits / invalidates [filter].
const String kDefaultStripFilterId = 'classic_warm';

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

/// Per-frame print cell aspect (width ÷ height) for a 2×6 strip.
///
/// Matches zenai `stripCompositor` cellGeometry at 300 DPI:
/// strip 600×1800, border 18, gutter 12 → cell 564×432.
const double kStripCellAspectRatio = 564 / 432;

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

/// Catalog payload from `GET /api/strip/filters`.
class StripFiltersCatalog {
  const StripFiltersCatalog({
    required this.brand,
    required this.shotCount,
    required this.filters,
    this.printSize = AppConstants.kPrintSizeStripDual2x6,
    this.copiesOnSheet = 2,
    this.printNote,
  });

  final String brand;
  final int shotCount;
  final List<StripFilter> filters;
  final String printSize;
  final int copiesOnSheet;
  final String? printNote;

  factory StripFiltersCatalog.fromJson(Map<String, dynamic> json) {
    final rawFilters = json['filters'];
    final filters = <StripFilter>[];
    if (rawFilters is List) {
      for (final item in rawFilters) {
        if (item is Map<String, dynamic>) {
          filters.add(StripFilter.fromJson(item));
        } else if (item is Map) {
          filters.add(StripFilter.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
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
      filters: filters,
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
    this.stripCompositeUrl,
    this.width,
    this.height,
    this.copiesOnSheet = 2,
    this.printSize = AppConstants.kPrintSizeStripDual2x6,
  });

  final String imageUrl;
  final String filter;

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
