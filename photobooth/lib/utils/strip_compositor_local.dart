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

class LocalStripOverlay {
  const LocalStripOverlay({
    required this.pngBytes,
    this.slots = const [],
  });

  final Uint8List pngBytes;
  final List<StripTemplateSlot> slots;
}

class LocalStripComposeRequest {
  const LocalStripComposeRequest({
    required this.sources,
    required this.filterId,
    required this.frameId,
    required this.single,
    required this.orientation,
    this.shotCount,
    this.mediaStore,
    this.overlay,
  });

  final List<String> sources;
  final String filterId;
  final String frameId;
  final bool single;
  final PrintOrientation orientation;

  /// Strip length (3 or 4). Defaults to [sources] length for strip composes.
  final int? shotCount;

  final LocalMediaStore? mediaStore;
  final LocalStripOverlay? overlay;

  /// Sources this request must receive before it can compose.
  int get expectedSourceCount =>
      single ? 1 : (shotCount ?? sources.length);
}

class _LocalStripIsolateInput {
  const _LocalStripIsolateInput({
    required this.sources,
    required this.filterId,
    required this.frameId,
    required this.single,
    required this.landscape,
    this.overlayPng,
    this.overlaySlots = const [],
  });

  final List<Uint8List> sources;
  final String filterId;
  final String frameId;
  final bool single;
  final bool landscape;
  final Uint8List? overlayPng;
  final List<double> overlaySlots;
}

/// Builds and persists a print-ready Classic sheet without WAN access.
///
/// Invalid or missing inputs fail open with `null`; callers can keep their
/// existing compose error UX. Disk-write failures return an inline JPEG URL.
Future<String?> composeLocalStripSheet(LocalStripComposeRequest request) async {
  final expected = request.expectedSourceCount;
  if (request.sources.length != expected) return null;
  if (!request.single && !kClassicStripShotCounts.contains(expected)) {
    return null;
  }
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
        overlayPng: request.overlay?.pngBytes,
        overlaySlots: _flattenOverlaySlots(request.overlay?.slots),
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
    overlay: _overlayFromIsolate(input.overlayPng, input.overlaySlots),
  );
}

/// Test hook for cell resize. Classic dual-strip cells contain-fit.
@visibleForTesting
img.Image? prepareLocalStripCellForTest(
  Uint8List bytes,
  int width,
  int height, {
  List<double>? matrix,
  bool contain = false,
  img.Color? letterbox,
}) =>
    _prepareCell(
      bytes,
      matrix,
      width,
      height,
      contain: contain,
      letterbox: letterbox,
    );

@visibleForTesting
Uint8List composeLocalStripSheetJpegForTest({
  required List<Uint8List> sourceBytes,
  required String filterId,
  required String frameId,
  required bool single,
  bool landscape = false,
  LocalStripOverlay? overlay,
}) {
  final width =
      single && landscape ? kLocalStripSheetHeight : kLocalStripSheetWidth;
  final height =
      single && landscape ? kLocalStripSheetWidth : kLocalStripSheetHeight;
  final sheet = img.Image(width: width, height: height, numChannels: 4);
  final background = single && overlay != null
      ? img.ColorRgb8(18, 18, 18)
      : _frameBackground(frameId);
  img.fill(sheet, color: background);
  final matrix = stripLookNeedsMatrixBake(filterId)
      ? stripLookColorMatrixValues(filterId)
      : null;
  if (single) {
    if (overlay != null) {
      _drawOccasionSingle(sheet, sourceBytes.single, matrix, overlay);
    } else {
      final hole = resolveClassicSinglePhotoHole(
        hasOverlay: false,
        landscape: landscape,
        frameId: frameId,
      );
      _drawSourceIntoCell(
        sheet,
        sourceBytes.single,
        matrix,
        _normalizedCell(width, height, hole, 0, 0),
        contain: true,
        letterbox: background,
      );
    }
  } else if (overlay != null) {
    _drawOccasionDualStrip(sheet, sourceBytes, matrix, overlay);
  } else {
    _drawDualStripCells(
      sheet,
      sourceBytes,
      matrix,
      frameId,
      sourceBytes.length,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(sheet, quality: kLocalStripJpegQuality),
  );
}

List<double> _flattenOverlaySlots(List<StripTemplateSlot>? slots) {
  if (slots == null || slots.isEmpty) return const [];
  final out = <double>[];
  for (final slot in slots) {
    out.addAll([slot.left, slot.top, slot.width, slot.height]);
  }
  return out;
}

LocalStripOverlay? _overlayFromIsolate(Uint8List? png, List<double> slots) {
  if (png == null || png.isEmpty) return null;
  return LocalStripOverlay(pngBytes: png, slots: _unflattenOverlaySlots(slots));
}

List<StripTemplateSlot> _unflattenOverlaySlots(List<double> values) {
  if (values.length < 4 || values.length % 4 != 0) return const [];
  final out = <StripTemplateSlot>[];
  for (var i = 0; i < values.length; i += 4) {
    out.add(
      StripTemplateSlot(
        left: values[i],
        top: values[i + 1],
        width: values[i + 2],
        height: values[i + 3],
      ),
    );
  }
  return out;
}

void _drawOccasionSingle(
  img.Image sheet,
  Uint8List source,
  List<double>? matrix,
  LocalStripOverlay overlay,
) {
  _drawSourceIntoCell(
    sheet,
    source,
    matrix,
    _normalizedCell(
      sheet.width,
      sheet.height,
      occasionSinglePhotoHole(
        overlay.slots,
        landscape: sheet.width > sheet.height,
      ),
      0,
      0,
    ),
    contain: false,
    letterbox: img.ColorRgb8(18, 18, 18),
  );
  _compositeOverlay(
    sheet,
    overlay.pngBytes,
    0,
    0,
    sheet.width,
    sheet.height,
  );
}

/// 4×6 occasion PNG, contain-centered on the print sheet (tests / unused bake).
@visibleForTesting
({int left, int top, int width, int height}) portraitChromeRectOnSheet(
  int sheetWidth,
  int sheetHeight,
) {
  const chromeAspect = kLocalStripSheetWidth / kLocalStripSheetHeight;
  final sheetAspect = sheetWidth / sheetHeight;
  if ((sheetAspect - chromeAspect).abs() < 0.02) {
    return (left: 0, top: 0, width: sheetWidth, height: sheetHeight);
  }
  if (sheetAspect > chromeAspect) {
    final width = (sheetHeight * chromeAspect).round().clamp(1, sheetWidth);
    return (
      left: (sheetWidth - width) ~/ 2,
      top: 0,
      width: width,
      height: sheetHeight,
    );
  }
  final height = (sheetWidth / chromeAspect).round().clamp(1, sheetHeight);
  return (
    left: 0,
    top: (sheetHeight - height) ~/ 2,
    width: sheetWidth,
    height: height,
  );
}

void _drawOccasionDualStrip(
  img.Image sheet,
  List<Uint8List> sources,
  List<double>? matrix,
  LocalStripOverlay overlay,
) {
  const stripDrawWidth =
      (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
  final stripOffsets = <int>[
    0,
    stripDrawWidth + kLocalStripCenterGutter,
  ];
  final slots = overlay.slots.length == sources.length
      ? overlay.slots
      : defaultOccasionStripSlots(sources.length);
  for (var i = 0; i < sources.length; i++) {
    final slot = slots[i];
    for (final stripLeft in stripOffsets) {
      _drawSourceIntoCell(
        sheet,
        sources[i],
        matrix,
        _normalizedCell(
          stripDrawWidth,
          kLocalStripSheetHeight,
          slot,
          stripLeft,
          0,
        ),
        contain: true,
        letterbox: img.ColorRgb8(18, 18, 18),
      );
    }
  }
  for (final stripLeft in stripOffsets) {
    _compositeOverlay(
      sheet,
      overlay.pngBytes,
      stripLeft,
      0,
      stripDrawWidth,
      kLocalStripSheetHeight,
    );
  }
}

_CellRect _normalizedCell(
  int spaceWidth,
  int spaceHeight,
  StripTemplateSlot slot,
  int originX,
  int originY,
) {
  final width = (slot.width * spaceWidth).round().clamp(1, spaceWidth);
  final height = (slot.height * spaceHeight).round().clamp(1, spaceHeight);
  return _CellRect(
    originX + (slot.left * spaceWidth).round(),
    originY + (slot.top * spaceHeight).round(),
    width,
    height,
  );
}

void _compositeOverlay(
  img.Image sheet,
  Uint8List png,
  int dstX,
  int dstY,
  int width,
  int height,
) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(png);
  } catch (_) {
    return;
  }
  if (decoded == null) return;
  final src =
      decoded.numChannels < 4 ? decoded.convert(numChannels: 4) : decoded;
  final resized = img.copyResize(
    src,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(
    sheet,
    resized,
    dstX: dstX,
    dstY: dstY,
    blend: img.BlendMode.alpha,
  );
}

void _drawDualStripCells(
  img.Image sheet,
  List<Uint8List> sources,
  List<double>? matrix,
  String frameId,
  int shotCount,
) {
  const stripDrawWidth = (kLocalStripSheetWidth - kLocalStripCenterGutter) ~/ 2;
  final stripOffsets = <int>[
    0,
    stripDrawWidth + kLocalStripCenterGutter,
  ];
  final rail = frameId == 'filmstrip' ? _filmRailWidth : kLocalStripBorder;
  final cellWidth = stripDrawWidth - rail * 2;
  // Sheet height is fixed by the print; fewer shots simply means taller cells.
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
      contain: true,
      letterbox: _frameBackground(frameId),
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
  _CellRect rect, {
  bool contain = false,
  img.Color? letterbox,
}) {
  final prepared = _prepareCell(
    bytes,
    matrix,
    rect.width,
    rect.height,
    contain: contain,
    letterbox: letterbox,
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
  img.Color? letterbox,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var source = img.bakeOrientation(decoded);
  if (matrix != null) {
    source = source.convert(numChannels: 4);
    applyStripLookColorMatrixInPlace(source, matrix);
  }
  return contain
      ? _resizeContain(source, width, height, letterbox)
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
      y: _coverCropTopY(
        sourceWidth: source.width,
        sourceHeight: source.height,
        destWidth: width,
        destHeight: height,
        cropHeight: cropHeight,
      ),
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

/// Portrait still → landscape well: keep heads. Landscape webcam → wide
/// 3/4-shot hole: center so the subject is not cropped off the bottom.
int _coverCropTopY({
  required int sourceWidth,
  required int sourceHeight,
  required int destWidth,
  required int destHeight,
  required int cropHeight,
}) {
  final extra = sourceHeight - cropHeight;
  if (extra <= 0) return 0;
  if (destWidth > destHeight && sourceHeight > sourceWidth) {
    return 0;
  }
  if (destWidth > destHeight) {
    return extra ~/ 2;
  }
  return (extra * 0.25).round();
}

img.Image _resizeContain(
  img.Image source,
  int width,
  int height, [
  img.Color? letterbox,
]) {
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
  img.fill(
    canvas,
    color: letterbox ?? img.ColorRgb8(255, 255, 255),
  );
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
