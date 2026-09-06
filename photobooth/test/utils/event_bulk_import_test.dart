import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/event_bulk_import.dart';

import '../helpers/tiny_jpeg.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Uint8List _jpegWithAscii(String ascii) {
  return Uint8List.fromList([...kTinyJpegBytes, ...ascii.codeUnits]);
}

Uint8List _webpHeader() {
  return Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
    0x57, 0x45, 0x42, 0x50, // WEBP
  ]);
}

void main() {
  test('parseJpegExifDateTime reads the last valid EXIF ASCII date', () {
    final bytes = _jpegWithAscii(
      '1999:01:01 00:00:00 then 2024:05:06 07:08:09',
    );
    expect(
      parseJpegExifDateTime(bytes),
      DateTime(2024, 5, 6, 7, 8, 9),
    );
  });

  test('parseJpegExifDateTime skips invalid dates and non-jpegs', () {
    expect(parseJpegExifDateTime(Uint8List(2)), isNull);
    expect(parseJpegExifDateTime(_pngBytes), isNull);
    expect(
      parseJpegExifDateTime(_jpegWithAscii('0000:00:00 00:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:13:01 00:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:00:01 00:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:01:00 00:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2101:01:01 00:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:01:01 99:00:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:01:01 00:99:00')),
      isNull,
    );
    expect(
      parseJpegExifDateTime(_jpegWithAscii('2024:01:01 00:00:99')),
      isNull,
    );
  });

  test('mime hint, magic, and unsupported types', () {
    expect(eventImportMimeFromHint('image/jpg', 'a.bin'), 'image/jpeg');
    expect(eventImportMimeFromHint('image/jpeg', 'a.bin'), 'image/jpeg');
    expect(eventImportMimeFromHint('image/png', 'a.bin'), 'image/png');
    expect(eventImportMimeFromHint('image/webp', 'a.bin'), 'image/webp');
    expect(eventImportMimeFromHint(null, 'shot.PNG'), 'image/png');
    expect(eventImportMimeFromHint(null, 'shot.WEBP'), 'image/webp');
    expect(eventImportMimeFromHint(null, 'shot.JPG'), 'image/jpeg');
    expect(eventImportMimeFromHint(null, 'shot.JPEG'), 'image/jpeg');
    expect(eventImportMimeFromHint('image/heic', 'shot.heic'), isNull);
    expect(eventImportMimeSupported('image/gif'), isFalse);
    expect(eventImportMimeSupported('image/jpeg'), isTrue);
    expect(eventImportMagicMime(kTinyJpegBytes), 'image/jpeg');
    expect(eventImportMagicMime(_pngBytes), 'image/png');
    expect(eventImportMagicMime(_webpHeader()), 'image/webp');
    expect(eventImportMagicMime(Uint8List.fromList([1, 2, 3])), isNull);
    expect(eventImportMagicMime(Uint8List.fromList('RIFF'.codeUnits)), isNull);
    expect(
      eventImportResolvedMime(kTinyJpegBytes, 'image/heic', 'x.heic'),
      'image/jpeg',
    );
    expect(
      eventImportResolvedMime(Uint8List.fromList([1, 2, 3]), null, 'x.heic'),
      isNull,
    );
  });

  test('data URL and session id helpers', () {
    expect(
      eventImportBytesToDataUrl(_pngBytes, 'image/png'),
      startsWith('data:image/png;base64,'),
    );
    expect(eventSessionIdFromCreateResponse({'id': '  abc  '}), 'abc');
    expect(eventSessionIdFromCreateResponse({'sessionId': 's2'}), 's2');
    expect(eventSessionIdFromCreateResponse({'id': ' '}), isNull);
    expect(eventSessionIdFromCreateResponse({}), isNull);
    expect(kEventSdImportSource, 'event-sd-import');
  });

  test('sort, toggle, discard, and selected subset', () {
    final early = EventBulkImportItem(
      id: 'a',
      name: 'b.jpg',
      bytes: kTinyJpegBytes,
      mime: 'image/jpeg',
      sortTime: null,
    );
    final later = EventBulkImportItem(
      id: 'b',
      name: 'a.jpg',
      bytes: kTinyJpegBytes,
      mime: 'image/jpeg',
      sortTime: DateTime(2024, 1, 2),
    );
    final mid = EventBulkImportItem(
      id: 'c',
      name: 'c.jpg',
      bytes: kTinyJpegBytes,
      mime: 'image/jpeg',
      sortTime: DateTime(2024, 1, 1),
    );
    final sameTimeZ = EventBulkImportItem(
      id: 'd',
      name: 'z.jpg',
      bytes: kTinyJpegBytes,
      mime: 'image/jpeg',
      sortTime: DateTime(2024, 1, 1),
    );
    final sorted = sortEventImportItems([early, later, mid, sameTimeZ]);
    expect(sorted.map((e) => e.id).toList(), ['c', 'd', 'b', 'a']);

    final toggled = toggleEventImportSelection(sorted, 'c');
    expect(eventImportSelected(toggled).map((e) => e.id), ['c']);
    expect(
      eventImportSelected(toggleEventImportSelection(toggled, 'missing'))
          .map((e) => e.id),
      ['c'],
    );
    expect(
      discardEventImportSelected(toggled).map((e) => e.id).toList(),
      ['d', 'b', 'a'],
    );
    expect(later.copyWith().selected, isFalse);
    expect(sortEventImportItems([later, early]).first.id, 'b');
  });

  test('picked files skip empty, unsupported, and sort by EXIF', () {
    final withExif = _jpegWithAscii('2020:02:03 04:05:06');
    final items = eventBulkImportItemsFromPicked(
      [
        EventImportPickedFile(
          name: 'empty.jpg',
          bytes: Uint8List(0),
          mimeType: 'image/jpeg',
        ),
        EventImportPickedFile(
          name: 'bad.heic',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/heic',
        ),
        EventImportPickedFile(
          name: 'later.jpg',
          bytes: kTinyJpegBytes,
          mimeType: 'image/jpeg',
          lastModified: DateTime(2024, 6, 1),
        ),
        EventImportPickedFile(
          name: 'exif.jpg',
          bytes: withExif,
          lastModified: DateTime(2025, 1, 1),
        ),
      ],
      batchId: 'batch',
    );
    expect(items.map((e) => e.name).toList(), ['exif.jpg', 'later.jpg']);
    expect(items.first.sortTime, DateTime(2020, 2, 3, 4, 5, 6));
    expect(items.first.id, 'batch-3');
  });

  test('XFile conversion skips empty, missing, and mtime failures', () async {
    final progress = <String>[];
    final items = await eventBulkImportItemsFromXFiles(
      [
        XFile.fromData(Uint8List(0), name: 'empty.jpg', mimeType: 'image/jpeg'),
        XFile('no-such-event-import-file.jpg'),
        XFile.fromData(
          kTinyJpegBytes,
          name: 'ok.jpg',
          mimeType: 'image/jpeg',
          path: '/tmp/ok.jpg',
        ),
        XFile.fromData(
          kTinyJpegBytes,
          name: 'dated.jpg',
          mimeType: 'image/jpeg',
          path: '/tmp/dated.jpg',
          lastModified: DateTime(2024, 3, 4, 5, 6, 7),
        ),
      ],
      batchId: 'x',
      onProgress: (done, total) => progress.add('$done/$total'),
    );
    expect(items, hasLength(2));
    expect(items.first.name, 'dated.jpg');
    expect(items.first.sortTime, DateTime(2024, 3, 4, 5, 6, 7));
    expect(progress.last, '4/4');
    expect(await eventImportPickedFileFromXFile(XFile('missing-again.jpg')), isNull);
  });

  test('file name falls back to path basename', () {
    expect(eventImportDisplayName(' named.jpg ', '/tmp/x.jpg'), 'named.jpg');
    expect(eventImportDisplayName('', '/tmp/from-path.jpg'), 'from-path.jpg');
    expect(eventImportDisplayName('', r'C:\dcim\x.jpg'), 'x.jpg');
    expect(eventImportDisplayName('', ''), 'photo.jpg');
    expect(eventImportDisplayName('', '/'), 'photo.jpg');
    expect(eventImportFileName(XFile('/tmp/from-path.jpg')), 'from-path.jpg');
  });
}
