import '../models/strip_models.dart';
import 'constants.dart';

/// Built-in Classic looks when `GET /api/strip/filters` fails or times out.
///
/// Keeps Pick-a-look usable on flaky booth networks instead of an empty
/// spinner / blank look column with Continue disabled.
StripFiltersCatalog stripFiltersCatalogFallback() {
  return const StripFiltersCatalog(
    brand: 'FotoFlashback',
    shotCount: kStripShotCount,
    printSize: AppConstants.kPrintSizeStripDual2x6,
    copiesOnSheet: 2,
    enableOsdScrub: false,
    filters: [
      StripFilter(
        id: 'classic_warm',
        name: 'Classic Warm',
        description: 'Soft warm grade',
        cssFilter: 'none',
      ),
      StripFilter(
        id: 'peach_glow',
        name: 'Peach Glow',
        description: 'Peachy highlights',
        cssFilter: 'none',
      ),
      StripFilter(
        id: 'soft_film',
        name: 'Soft Film',
        description: 'Gentle film lift',
        cssFilter: 'none',
      ),
      StripFilter(
        id: 'golden_hour',
        name: 'Golden Hour',
        description: 'Warm sunset tone',
        cssFilter: 'none',
      ),
      StripFilter(
        id: 'mono',
        name: 'Mono',
        description: 'Black and white',
        cssFilter: 'grayscale(1)',
      ),
      StripFilter(
        id: 'clean',
        name: 'Clean',
        description: 'No grade',
        cssFilter: 'none',
      ),
    ],
    frames: [
      StripFrame(
        id: kDefaultStripFrameId,
        name: 'Classic',
        description: 'Default frame',
      ),
    ],
    stickers: [
      StripSticker(
        id: kDefaultStripStickerId,
        name: 'None',
        description: 'No sticker',
      ),
    ],
  );
}
