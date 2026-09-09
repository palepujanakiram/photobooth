import 'dart:typed_data';

/// A downscaled, print-ready copy of an original.
class DownscaleResult {
  const DownscaleResult({
    required this.bytes,
    required this.width,
    required this.height,
    this.thumbBytes,
    this.thumbWidth,
    this.thumbHeight,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Grid thumbnail encoded from the same decode, when one was asked for.
  ///
  /// Null when [DownscaleTarget.thumbShortSide] was not requested, or when the
  /// original is already smaller than the thumbnail target — upscaling would
  /// spend bytes for no extra detail.
  final Uint8List? thumbBytes;
  final int? thumbWidth;
  final int? thumbHeight;

  bool get hasThumb => thumbBytes != null && thumbBytes!.isNotEmpty;
}

/// Produces the print-ready derivative the device keeps.
///
/// The original is never copied off the card; only this output is stored, which
/// is what takes a 3,000-frame event from roughly 18 GB to 4 GB.
///
/// Implementations must apply EXIF orientation, because the re-encode drops the
/// orientation tag and a prints-sideways bug is otherwise invisible until paper
/// comes out of the printer.
abstract class ImageDownscaler {
  /// Scales so the **short side** reaches [targetShortSide], preserving aspect
  /// ratio, and never upscales.
  ///
  /// The short side is the constraint because `DnpImageProcessor` cover-fits a
  /// photo onto the print raster: at 300 dpi the DS-RX1's native width is
  /// 1920 px, so a derivative whose short side reaches 1920 has full native
  /// quality at every size the printer offers.
  ///
  /// Pass [thumbShortSide] to also get the grid thumbnail out of the same
  /// decode. Zero skips it.
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = 4096,
    int quality = 88,
    int thumbShortSide = 0,
  });
}

/// Target dimensions for a downscale, derived from the DNP print raster.
abstract final class DownscaleTarget {
  /// DS-RX1 / DS-RX1HS native width at 300 dpi, from `DnpPrintSize.kt`.
  static const int dnpNativeWidth = 1920;

  /// Bounds a panorama so an extreme aspect ratio cannot produce a huge file.
  static const int maxLongSide = 4096;

  static const int jpegQuality = 88;

  /// Short-side target for a given quality multiplier.
  ///
  /// A factor of 1.0 lands exactly on the printer's native width. Above that
  /// buys headroom for the printer's own resampling at the cost of disk.
  static int shortSideFor(double qualityFactor) {
    final scaled = (dnpNativeWidth * qualityFactor).round();
    if (scaled < 320) return 320;
    if (scaled > maxLongSide) return maxLongSide;
    return scaled;
  }
}
