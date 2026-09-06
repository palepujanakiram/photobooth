import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Session create `source` for Capture-station SD / folder ingest.
const String kEventSdImportSource = 'event-sd-import';

enum EventBulkImportPhase { reading, uploading }

/// Injected picker so the Capture station ViewModel stays unit-testable.
class EventCaptureImportHooks {
  const EventCaptureImportHooks({required this.pickImages});

  final Future<List<XFile>> Function() pickImages;
}

class EventBulkImportProgress {
  const EventBulkImportProgress({
    required this.done,
    required this.total,
    this.phase = EventBulkImportPhase.uploading,
  });

  final int done;
  final int total;
  final EventBulkImportPhase phase;
}

class EventImportPickedFile {
  const EventImportPickedFile({
    required this.name,
    required this.bytes,
    this.mimeType,
    this.lastModified,
  });

  final String name;
  final Uint8List bytes;
  final String? mimeType;
  final DateTime? lastModified;
}

class EventBulkImportItem {
  const EventBulkImportItem({
    required this.id,
    required this.name,
    required this.bytes,
    required this.mime,
    this.sortTime,
    this.selected = false,
  });

  final String id;
  final String name;
  final Uint8List bytes;
  final String mime;
  final DateTime? sortTime;
  final bool selected;

  EventBulkImportItem copyWith({bool? selected}) {
    return EventBulkImportItem(
      id: id,
      name: name,
      bytes: bytes,
      mime: mime,
      sortTime: sortTime,
      selected: selected ?? this.selected,
    );
  }
}

final _exifDatePattern = RegExp(
  r'(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})',
);

/// DateTimeOriginal (or any EXIF ASCII date) from a JPEG APP1 segment.
DateTime? parseJpegExifDateTime(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  final limit = math.min(bytes.length, 65536);
  final text = String.fromCharCodes(bytes.sublist(0, limit));
  DateTime? latest;
  for (final match in _exifDatePattern.allMatches(text)) {
    final parsed = _exifMatchToDate(match);
    if (parsed != null) latest = parsed;
  }
  return latest;
}

DateTime? _exifMatchToDate(RegExpMatch match) {
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (year < 1990 || year > 2100) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;
  return DateTime(year, month, day, hour, minute, second);
}

String? eventImportMimeFromHint(String? mimeHint, String name) {
  final m = (mimeHint ?? '').trim().toLowerCase();
  if (m == 'image/jpg' || m == 'image/jpeg') return 'image/jpeg';
  if (m == 'image/png') return 'image/png';
  if (m == 'image/webp') return 'image/webp';
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

bool eventImportMimeSupported(String mime) {
  return mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp';
}

String? eventImportMagicMime(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (_isWebp(bytes)) return 'image/webp';
  return null;
}

bool _isWebp(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final webp = String.fromCharCodes(bytes.sublist(8, 12));
  return riff == 'RIFF' && webp == 'WEBP';
}

String? eventImportResolvedMime(
  Uint8List bytes,
  String? mimeHint,
  String name,
) {
  final hinted = eventImportMimeFromHint(mimeHint, name);
  if (hinted != null && eventImportMimeSupported(hinted)) return hinted;
  return eventImportMagicMime(bytes);
}

String eventImportBytesToDataUrl(Uint8List bytes, String mime) {
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

String? eventSessionIdFromCreateResponse(Map<String, dynamic> response) {
  for (final key in const ['id', 'sessionId']) {
    final value = response[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

List<EventBulkImportItem> sortEventImportItems(List<EventBulkImportItem> items) {
  final copy = List<EventBulkImportItem>.from(items);
  copy.sort(_compareImportItems);
  return copy;
}

int _compareImportItems(EventBulkImportItem a, EventBulkImportItem b) {
  final at = a.sortTime;
  final bt = b.sortTime;
  if (at != null && bt != null) {
    final byTime = at.compareTo(bt);
    if (byTime != 0) return byTime;
  } else if (at != null) {
    return -1;
  } else if (bt != null) {
    return 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

List<EventBulkImportItem> toggleEventImportSelection(
  List<EventBulkImportItem> items,
  String id,
) {
  return [
    for (final item in items)
      if (item.id == id) item.copyWith(selected: !item.selected) else item,
  ];
}

List<EventBulkImportItem> discardEventImportSelected(
  List<EventBulkImportItem> items,
) {
  return items.where((item) => !item.selected).toList();
}

List<EventBulkImportItem> eventImportSelected(List<EventBulkImportItem> items) {
  return items.where((item) => item.selected).toList();
}

List<EventBulkImportItem> eventBulkImportItemsFromPicked(
  List<EventImportPickedFile> files, {
  required String batchId,
}) {
  final items = <EventBulkImportItem>[];
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final mime = eventImportResolvedMime(file.bytes, file.mimeType, file.name);
    if (mime == null || file.bytes.isEmpty) continue;
    items.add(
      EventBulkImportItem(
        id: '$batchId-$i',
        name: file.name,
        bytes: file.bytes,
        mime: mime,
        sortTime: parseJpegExifDateTime(file.bytes) ?? file.lastModified,
      ),
    );
  }
  return sortEventImportItems(items);
}

String eventImportDisplayName(String name, String path) {
  final trimmedName = name.trim();
  if (trimmedName.isNotEmpty) return trimmedName;
  final trimmedPath = path.trim();
  if (trimmedPath.isEmpty) return 'photo.jpg';
  final base = trimmedPath.split(RegExp(r'[/\\]')).last.trim();
  return base.isEmpty ? 'photo.jpg' : base;
}

String eventImportFileName(XFile file) {
  return eventImportDisplayName(file.name, file.path);
}

Future<EventImportPickedFile?> eventImportPickedFileFromXFile(XFile file) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    DateTime? modified;
    try {
      modified = await file.lastModified();
    } catch (_) {}
    return EventImportPickedFile(
      name: eventImportFileName(file),
      bytes: bytes,
      mimeType: file.mimeType,
      lastModified: modified,
    );
  } catch (_) {
    return null;
  }
}

Future<List<EventBulkImportItem>> eventBulkImportItemsFromXFiles(
  List<XFile> files, {
  required String batchId,
  void Function(int done, int total)? onProgress,
}) async {
  final picked = <EventImportPickedFile>[];
  for (var i = 0; i < files.length; i++) {
    onProgress?.call(i, files.length);
    final one = await eventImportPickedFileFromXFile(files[i]);
    if (one != null) picked.add(one);
  }
  onProgress?.call(files.length, files.length);
  return eventBulkImportItemsFromPicked(picked, batchId: batchId);
}
