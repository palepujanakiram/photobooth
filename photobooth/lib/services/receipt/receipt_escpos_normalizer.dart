import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'receipt_printer_profile.dart';

/// Resizes ESC/POS raster images so receipt photos fit 80mm paper width.
abstract final class ReceiptEscPosNormalizer {
  /// Scales embedded raster images to [targetWidthDots] (default 576 / 80mm).
  static Uint8List normalize(
    Uint8List payload, {
    int targetWidthDots = ReceiptPrinterProfile.printWidthDots,
  }) {
    if (payload.isEmpty || targetWidthDots <= 0) return payload;

    final out = BytesBuilder(copy: false);
    var index = 0;
    while (index < payload.length) {
      final raster = _tryParseGsV0(payload, index);
      if (raster != null) {
        out.add(payload.sublist(index, raster.start));
        out.add(_rescaleSegment(raster, targetWidthDots));
        index = raster.end;
        continue;
      }

      final legacy = _tryParseEscStar(payload, index);
      if (legacy != null) {
        out.add(payload.sublist(index, legacy.start));
        out.add(_rescaleSegment(legacy, targetWidthDots));
        index = legacy.end;
        continue;
      }

      out.addByte(payload[index]);
      index++;
    }
    return out.toBytes();
  }
}

class _RasterSegment {
  const _RasterSegment({
    required this.start,
    required this.end,
    required this.widthBytes,
    required this.heightDots,
    required this.mode,
    required this.data,
    required this.originalBytes,
    required this.isGsV0,
  });

  final int start;
  final int end;
  final int widthBytes;
  final int heightDots;
  final int mode;
  final Uint8List data;
  final Uint8List originalBytes;
  final bool isGsV0;
}

_RasterSegment? _tryParseGsV0(Uint8List payload, int index) {
  if (index + 8 > payload.length) return null;
  if (payload[index] != 0x1D || payload[index + 1] != 0x76 || payload[index + 2] != 0x30) {
    return null;
  }

  final mode = payload[index + 3];
  final widthBytes = payload[index + 4] | (payload[index + 5] << 8);
  final heightDots = payload[index + 6] | (payload[index + 7] << 8);
  if (widthBytes <= 0 || heightDots <= 0) return null;

  final dataStart = index + 8;
  final dataLength = widthBytes * heightDots;
  final dataEnd = dataStart + dataLength;
  if (dataEnd > payload.length) return null;

  return _RasterSegment(
    start: index,
    end: dataEnd,
    widthBytes: widthBytes,
    heightDots: heightDots,
    mode: mode,
    data: Uint8List.sublistView(payload, dataStart, dataEnd),
    originalBytes: Uint8List.sublistView(payload, index, dataEnd),
    isGsV0: true,
  );
}

_RasterSegment? _tryParseEscStar(Uint8List payload, int index) {
  if (index + 5 > payload.length) return null;
  if (payload[index] != 0x1B || payload[index + 1] != 0x2A) return null;

  final mode = payload[index + 2];
  if (mode != 0x00 && mode != 0x01 && mode != 0x20 && mode != 0x21) {
    return null;
  }

  final widthBytes = payload[index + 3] | (payload[index + 4] << 8);
  final heightDots = _escStarHeightForMode(mode);
  if (widthBytes <= 0 || heightDots <= 0) return null;

  final dataStart = index + 5;
  final dataLength = widthBytes * heightDots;
  final dataEnd = dataStart + dataLength;
  if (dataEnd > payload.length) return null;

  return _RasterSegment(
    start: index,
    end: dataEnd,
    widthBytes: widthBytes,
    heightDots: heightDots,
    mode: mode,
    data: Uint8List.sublistView(payload, dataStart, dataEnd),
    originalBytes: Uint8List.sublistView(payload, index, dataEnd),
    isGsV0: false,
  );
}

int _escStarHeightForMode(int mode) {
  return switch (mode) {
    0x00 || 0x01 => 8,
    0x20 || 0x21 => 24,
    _ => 0,
  };
}

@visibleForTesting
int escStarHeightForModeForTest(int mode) => _escStarHeightForMode(mode);

int _modeWidthMultiplier(int mode) {
  return switch (mode) {
    1 || 3 => 2,
    _ => 1,
  };
}

int _modeHeightMultiplier(int mode) {
  return switch (mode) {
    2 || 3 => 2,
    _ => 1,
  };
}

Uint8List _rescaleSegment(_RasterSegment segment, int targetWidthDots) {
  final sourceWidthDots = segment.isGsV0
      ? segment.widthBytes * 8 * _modeWidthMultiplier(segment.mode)
      : segment.widthBytes * 8;
  final sourceHeightDots = segment.isGsV0
      ? segment.heightDots * _modeHeightMultiplier(segment.mode)
      : segment.heightDots;
  final rescaled = _rescaleMonochrome(
    data: segment.data,
    widthBytes: segment.widthBytes,
    heightDots: segment.heightDots,
    sourceWidthDots: sourceWidthDots,
    sourceHeightDots: sourceHeightDots,
    targetWidthDots: targetWidthDots,
  );
  if (rescaled == null || sourceWidthDots == targetWidthDots) {
    return segment.originalBytes;
  }

  if (segment.isGsV0) {
    final header = Uint8List(8);
    header[0] = 0x1D;
    header[1] = 0x76;
    header[2] = 0x30;
    header[3] = 0x00;
    header[4] = rescaled.widthBytes & 0xFF;
    header[5] = (rescaled.widthBytes >> 8) & 0xFF;
    header[6] = rescaled.heightDots & 0xFF;
    header[7] = (rescaled.heightDots >> 8) & 0xFF;
    return Uint8List.fromList([...header, ...rescaled.data]);
  }

  final header = Uint8List(5);
  header[0] = 0x1B;
  header[1] = 0x2A;
  header[2] = 0x00;
  header[3] = rescaled.widthBytes & 0xFF;
  header[4] = (rescaled.widthBytes >> 8) & 0xFF;
  return Uint8List.fromList([...header, ...rescaled.data]);
}

({int widthBytes, int heightDots, Uint8List data})? _rescaleMonochrome({
  required Uint8List data,
  required int widthBytes,
  required int heightDots,
  required int sourceWidthDots,
  required int sourceHeightDots,
  required int targetWidthDots,
}) {
  if (sourceWidthDots <= 0 || sourceHeightDots <= 0) return null;
  if (sourceWidthDots == targetWidthDots) {
    return (widthBytes: widthBytes, heightDots: heightDots, data: data);
  }

  final source = _unpackMonochrome(
    data: data,
    widthBytes: widthBytes,
    heightDots: heightDots,
    widthDots: sourceWidthDots,
    height: sourceHeightDots,
  );
  final targetHeight = math.max(
    1,
    (sourceHeightDots * targetWidthDots / sourceWidthDots).round(),
  );
  final resized = img.copyResize(
    source,
    width: targetWidthDots,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );
  final packed = _packMonochrome(resized);
  return (
    widthBytes: packed.widthBytes,
    heightDots: packed.heightDots,
    data: packed.data,
  );
}

img.Image _unpackMonochrome({
  required Uint8List data,
  required int widthBytes,
  required int heightDots,
  required int widthDots,
  required int height,
}) {
  final image = img.Image(width: widthDots, height: height);
  for (var y = 0; y < height; y++) {
    for (var xByte = 0; xByte < widthBytes; xByte++) {
      final byteIndex = y * widthBytes + xByte;
      if (byteIndex >= data.length) break;
      final value = data[byteIndex];
      for (var bit = 0; bit < 8; bit++) {
        final x = xByte * 8 + bit;
        if (x >= widthDots) break;
        final on = (value & (0x80 >> bit)) != 0;
        image.setPixelRgb(x, y, on ? 0 : 255, on ? 0 : 255, on ? 0 : 255);
      }
    }
  }
  return image;
}

({int widthBytes, int heightDots, Uint8List data}) _packMonochrome(img.Image image) {
  final widthDots = image.width;
  final heightDots = image.height;
  final widthBytes = (widthDots + 7) ~/ 8;
  final out = Uint8List(widthBytes * heightDots);

  for (var y = 0; y < heightDots; y++) {
    for (var xByte = 0; xByte < widthBytes; xByte++) {
      var value = 0;
      for (var bit = 0; bit < 8; bit++) {
        final x = xByte * 8 + bit;
        if (x >= widthDots) continue;
        final pixel = image.getPixel(x, y);
        final lum = img.getLuminance(pixel);
        if (lum < 128) {
          value |= 0x80 >> bit;
        }
      }
      out[y * widthBytes + xByte] = value;
    }
  }

  return (widthBytes: widthBytes, heightDots: heightDots, data: out);
}
