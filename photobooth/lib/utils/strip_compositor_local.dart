import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/strip_models.dart';
import '../services/image_cache_source.dart';
import '../services/local_guest_media_write.dart';
import '../services/local_media_store.dart';
import 'logger.dart';
import 'print_orientation.dart';
import 'strip_look_color_matrices.dart';
import 'strip_look_matrix_bake.dart';

const int kLocalStripSheetWidth = 1200;
const int kLocalStripSheetHeight = 1800;
const int kLocalStripWidth = 600;
const int kLocalStripBorder = 10;
const int kLocalStripBorderTop = 10;
const int kLocalStripBorderBottom = 10;
const int kLocalStripGutter = 10;
const int kLocalStripCenterGutter = 16;
const int kLocalStripJpegQuality = 92;

const int _filmRailWidth = 36;
const int _filmHoleWidth = 18;
const int _filmHoleHeight = 24;
const int _filmHolePitch = 46;
const int _filmHoleStartY = 28;
const int _filmHoleInset = 4;

class LocalStripComposeRequest {
  const LocalStripComposeRequest({
    required this.sources,
    required this.filterId,
    required this.frameId,
    required this.single,
    required this.orientation,
    this.mediaStore,
  });

  final List<String> sources;
  final String filterId;
  final String frameId;
  final bool single;
  final PrintOrientation orientation;
  final LocalMediaStore? mediaStore;
}

class _LocalStripIsolateInput {
  const _LocalStripIsolateInput({
    required this.sources,
    required this.filterId,
    required this.frameId,
    required this.single,
    required this.landscape,
  });

  final List<Uint8List> sources;
  final String filterId;
  final String frameId;
  final bool single;
  final bool landscape;
}

/// Builds and persists a print-ready Classic sheet without WAN access.
///
/// Invalid or missing inputs fail open with `null`; callers can keep their
/// existing compose error UX. Disk-write failures return an inline JPEG URL.
Future<String?> composeLocalStripSheet(LocalStripComposeRequest request) async {
  final expected = request.single ? 1 : request.sources.length;
  if (expected != 1 && expected != 3 && expected != kStripShotCount) {
    return null;
  }
  if (request.sources.length != expected) return null;
  try {
    final bytes = <Uint8List>[];
    for (final source in request.sources) {
      final loaded = await _loadSourceBytes(source, request.mediaStore);
      if (loaded == null || loaded.isEmpty) return null;
      bytes.add(loaded);
    }
    final jpeg = await compute(
      _composeLocalStripSheetIsolate,
      _LocalStripIsolateInput(
        sources: bytes,
        filterId: request.filterId,
        frameId: request.frameId,
        single: request.single,
        landscape: request.orientation == PrintOrientation.landscape,
      ),
    );
    if (jpeg.isEmpty) return null;
    final written = await putGuestJpeg(
      prefix: kGuestMediaPrefixFotoflashback,
      bytes: jpeg,
      store: request.mediaStore,
    );
    return written?.sessionUrl ??
        'data:image/jpeg;base64,${base64Encode(jpeg)}';
  } catch (error, stackTrace) {
    AppLogger.warning(
      'Local Classic sheet compose failed',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

Future<Uint8List?> _loadSourceBytes(
  String source,
  LocalMediaStore? mediaStore,
) async {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  final inline = extractInlineImageDataUrl(trimmed);
  if (inline != null) {
    final decoded = decodeInlineImageDataUrl(inline);
    return decoded == null ? null : Uint8List.fromList(decoded);
  }
  final stored = await (mediaStore ?? LocalMediaStore()).fileForUrl(trimmed);
  if (stored != null) return stored.readAsBytes();
  if (_isRemoteSource(trimmed)) return null;
  final path = trimmed.startsWith(kFileUrlSchemePrefix)
      ? (Uri.tryParse(trimmed)?.toFilePath() ?? trimmed)
      : trimmed;
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

bool _isRemoteSource(String source) {
  final lower = source.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('$kLocalMediaScheme:') ||
      source.contains(kApiImgPathPrefix);
}

Uint8List _composeLocalStripSheetIsolate(_LocalStripIsolateInput input) {
  return composeLocalStripSheetJpegForTest(
    sourceBytes: input.sources,
    filterId: input.filterId,
    frameId: input.frameId,
    single: input.single,
    landscape: input.landscape,
  );
}

@visibleForTesting
Uint8List composeLocalStripSheetJpegForTest({
  required List<Uint8List> sourceBytes,
  required String filterId,
  required String frameId,
  required bool single,
  bool landscape = false,
}) {
  final width =
      single && landscape ? kLocalStripSheetHeight : kLocalStripSheetWidth;
  final height =
      single && landscape ? kLocalStripSheetWidth : kLocalStripSheetHeight;
  final sheet = img.Image(width: width, height: height);
  final background = _frameBackground(frameId);
  img.fill(sheet, color: background);
  final matrix = stripLookNeedsMatrixBake(filterId)
      ? stripLookColorMatrixValues(filterId)
      : null;
  if (single) {
    _drawSourceIntoCell(
      sheet,
      sourceBytes.single,
      matrix,
      _CellRect(0, 0, width, height),
    );
  } else {
    _drawDualStripCells(sheet, sourceBytes, matrix, frameId);
  }
  return Uint8List.fromList(
    img.encodeJpg(sheet, quality: kLocalStripJpegQuality),
  );
}

void _drawDualStripCells(
  img.Image sheet,
  List<Uint8List> sources,
  List<double>? matrix,
  String frameId,
) {
  const stripDrawWidth = (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
  final stripOffsets = <int>[
    0,
    stripDrawWidth + kLocalStripCenterGutter,
  ];
  final rail = frameId == 'filmstrip' ? _filmRailWidth : kLocalStripBorder;
  final cellWidth = stripDrawWidth - rail * 2;
  final shotCount = sources.length;
  final innerHeight = kLocalStripSheetHeight -
      kLocalStripBorderTop -
      kLocalStripBorderBottom -
      kLocalStripGutter * (shotCount - 1);
  final cellHeight = innerHeight ~/ shotCount;
  for (var i = 0; i < sources.length; i++) {
    final top =
        kLocalStripBorderTop + i * (cellHeight + kLocalStripGutter);
    final prepared = _prepareCell(
      sources[i],
      matrix,
      cellWidth,
      cellHeight,
    );
    if (prepared == null) continue;
    for (final stripLeft in stripOffsets) {
      img.compositeImage(sheet, prepared, dstX: stripLeft + rail, dstY: top);
    }
  }
  if (frameId == 'filmstrip') {
    for (final stripLeft in stripOffsets) {
      _drawFilmSprockets(sheet, stripLeft, stripDrawWidth);
    }
  }
}

void _drawSourceIntoCell(
  img.Image sheet,
  Uint8List bytes,
  List<double>? matrix,
  _CellRect rect,
) {
  final prepared = _prepareCell(
    bytes,
    matrix,
    rect.width,
    rect.height,
  );
  if (prepared != null) {
    img.compositeImage(sheet, prepared, dstX: rect.left, dstY: rect.top);
  }
}

img.Image? _prepareCell(
  Uint8List bytes,
  List<double>? matrix,
  int width,
  int height, {
  bool contain = false,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var source = img.bakeOrientation(decoded);
  if (matrix != null) {
    source = source.convert(numChannels: 4);
    applyStripLookColorMatrixInPlace(source, matrix);
  }
  return contain
      ? _resizeContain(source, width, height)
      : _resizeCover(source, width, height);
}

img.Image _resizeCover(img.Image source, int width, int height) {
  final targetAspect = width / height;
  final sourceAspect = source.width / source.height;
  late final img.Image cropped;
  if (sourceAspect > targetAspect) {
    final cropWidth =
        (source.height * targetAspect).round().clamp(1, source.width);
    cropped = img.copyCrop(
      source,
      x: (source.width - cropWidth) ~/ 2,
      y: 0,
      width: cropWidth,
      height: source.height,
    );
  } else {
    final cropHeight =
        (source.width / targetAspect).round().clamp(1, source.height);
    cropped = img.copyCrop(
      source,
      x: 0,
      y: ((source.height - cropHeight) * 0.25).round(),
      width: source.width,
      height: cropHeight,
    );
  }
  return img.copyResize(
    cropped,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
}

img.Image _resizeContain(img.Image source, int width, int height) {
  final scale = (width / source.width < height / source.height)
      ? width / source.width
      : height / source.height;
  final resized = img.copyResize(
    source,
    width: (source.width * scale).round().clamp(1, width),
    height: (source.height * scale).round().clamp(1, height),
    interpolation: img.Interpolation.average,
  );
  final canvas = img.Image(width: width, height: height);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(
    canvas,
    resized,
    dstX: (width - resized.width) ~/ 2,
    dstY: (height - resized.height) ~/ 2,
  );
  return canvas;
}

void _drawFilmSprockets(img.Image sheet, int stripLeft, int stripWidth) {
  final leftX = stripLeft + _filmHoleInset;
  final rightX = stripLeft + stripWidth - _filmHoleInset - _filmHoleWidth;
  for (var y = _filmHoleStartY;
      y + _filmHoleHeight < kLocalStripSheetHeight;
      y += _filmHolePitch) {
    _fillRect(sheet, leftX, y, _filmHoleWidth, _filmHoleHeight);
    _fillRect(sheet, rightX, y, _filmHoleWidth, _filmHoleHeight);
  }
}

void _fillRect(img.Image image, int x, int y, int width, int height) {
  img.fillRect(
    image,
    x1: x,
    y1: y,
    x2: x + width - 1,
    y2: y + height - 1,
    color: img.ColorRgb8(255, 255, 255),
  );
}

img.Color _frameBackground(String frameId) {
  switch (frameId) {
    case 'noir':
      return img.ColorRgb8(18, 18, 22);
    case 'filmstrip':
      return img.ColorRgb8(10, 10, 10);
    default:
      return img.ColorRgb8(255, 255, 255);
  }
}

class _CellRect {
  const _CellRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;
}
