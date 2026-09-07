import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_diff.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_source.dart';

IngestCandidate candidate({
  String path = 'DCIM/100CANON/IMG_0001.JPG',
  String? name,
  int size = 6000000,
  int modified = 1000,
  int? captured,
  String? mime = 'image/jpeg',
  String volume = 'VOL1',
}) {
  final display = name ?? path.split('/').last;
  return IngestCandidate(
    sourceId: volume,
    relativePath: path,
    displayName: display,
    sizeBytes: size,
    modifiedAtMs: modified,
    capturedAtMs: captured,
    mimeType: mime,
    uri: '/tmp/$display',
  );
}

void main() {
  group('sourceRef', () {
    test('includes volume, path, size and mtime', () {
      expect(
        candidate().sourceRef,
        'VOL1:DCIM/100CANON/IMG_0001.JPG:6000000:1000',
      );
    });

    test('a reformatted card produces a different key for the same path', () {
      // Canon auto-reset numbering restarts at IMG_0001 after a format, so the
      // path repeats for a genuinely different photograph.
      final before = candidate(size: 6000000, modified: 1000);
      final after = candidate(size: 5211334, modified: 99999);
      expect(before.sourceRef, isNot(after.sourceRef));
    });

    test('folder is the directory portion', () {
      expect(candidate().folder, 'DCIM/100CANON');
      expect(candidate(path: 'IMG.JPG').folder, '');
    });

    test('sortKey prefers capture time over mtime', () {
      expect(candidate(captured: 500, modified: 900).sortKey, 500);
      expect(candidate(modified: 900).sortKey, 900);
    });
  });

  group('folderInScope', () {
    test('matches the root itself and its descendants', () {
      expect(IngestDiff.folderInScope('DCIM', ['DCIM']), isTrue);
      expect(IngestDiff.folderInScope('DCIM/100CANON', ['DCIM']), isTrue);
    });

    test('does not match a sibling with the same prefix', () {
      expect(IngestDiff.folderInScope('DCIMX', ['DCIM']), isFalse);
      expect(IngestDiff.folderInScope('Pictures', ['DCIM']), isFalse);
    });

    test('is case-insensitive and tolerates stray separators', () {
      expect(IngestDiff.folderInScope('dcim/100canon', ['/DCIM/']), isTrue);
    });

    test('an empty scan list includes everything', () {
      expect(IngestDiff.folderInScope('Pictures', const []), isTrue);
    });
  });

  group('IngestMimeTypes', () {
    test('accepts jpeg, heic and png', () {
      for (final mime in ['image/jpeg', 'image/heic', 'image/png']) {
        expect(IngestMimeTypes.isImportable(candidate(mime: mime)), isTrue);
      }
    });

    test('rejects RAW and reports it as RAW', () {
      final raw = candidate(name: 'IMG_0631.CR3', mime: null);
      expect(IngestMimeTypes.isImportable(raw), isFalse);
      expect(IngestMimeTypes.isRaw(raw), isTrue);
    });

    test('falls back to the extension when no MIME is given', () {
      expect(
        IngestMimeTypes.isImportable(candidate(name: 'a.JPG', mime: null)),
        isTrue,
      );
      expect(
        IngestMimeTypes.isImportable(candidate(name: 'a.txt', mime: null)),
        isFalse,
      );
    });

    test('an explicit video MIME beats a misleading filename', () {
      expect(
        IngestMimeTypes.isImportable(
          candidate(name: 'clip.jpg', mime: 'video/mp4'),
        ),
        isFalse,
      );
    });
  });

  group('scan', () {
    test('everything is new on a first import', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/100CANON/A.JPG'),
          candidate(path: 'DCIM/100CANON/B.JPG'),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates, hasLength(2));
      expect(result.alreadyImported, 0);
      expect(result.hasNew, isTrue);
    });

    test('a rescan of a known card finds nothing new', () {
      final a = candidate(path: 'DCIM/100CANON/A.JPG');
      final b = candidate(path: 'DCIM/100CANON/B.JPG');
      final result = IngestDiff.scan(
        candidates: [a, b],
        knownSourceRefs: {a.sourceRef, b.sourceRef},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates, isEmpty);
      expect(result.alreadyImported, 2);
    });

    test('a partially refilled card imports only the new frames', () {
      final old = candidate(path: 'DCIM/100CANON/A.JPG');
      final fresh = candidate(path: 'DCIM/100CANON/B.JPG');
      final result = IngestDiff.scan(
        candidates: [old, fresh],
        knownSourceRefs: {old.sourceRef},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates.single.relativePath, 'DCIM/100CANON/B.JPG');
      expect(result.alreadyImported, 1);
    });

    test('phone folders outside DCIM are excluded by default', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/100CANON/A.JPG'),
          candidate(path: 'Pictures/screenshot.png', mime: 'image/png'),
          candidate(path: 'Download/meme.jpg'),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates, hasLength(1));
      expect(result.outsideScanFolders, 2);
    });

    test('the operator can widen the scan to an extra folder', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/100CANON/A.JPG'),
          candidate(path: 'Pictures/b.jpg'),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
        extraFolders: const {'Pictures'},
      );
      expect(result.newCandidates, hasLength(2));
      expect(result.outsideScanFolders, 0);
    });

    test('recurses every DCIM subfolder after a rollover', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/100CANON/A.JPG'),
          candidate(path: 'DCIM/101CANON/B.JPG'),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates, hasLength(2));
    });

    test('folder summary counts every folder, scanned or not', () {
      final known = candidate(path: 'DCIM/100CANON/A.JPG');
      final result = IngestDiff.scan(
        candidates: [
          known,
          candidate(path: 'DCIM/100CANON/B.JPG'),
          candidate(path: 'Pictures/c.jpg'),
        ],
        knownSourceRefs: {known.sourceRef},
        scanFolders: const ['DCIM'],
      );
      final byName = {for (final f in result.folders) f.folder: f};
      expect(byName['DCIM/100CANON']!.total, 2);
      expect(byName['DCIM/100CANON']!.newCount, 1);
      expect(byName['DCIM/100CANON']!.selectedByDefault, isTrue);
      expect(byName['Pictures']!.total, 1);
      expect(byName['Pictures']!.selectedByDefault, isFalse);
    });

    test('results are ordered oldest first', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/C.JPG', captured: 300),
          candidate(path: 'DCIM/A.JPG', captured: 100),
          candidate(path: 'DCIM/B.JPG', captured: 200),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
      );
      expect(
        result.newCandidates.map((c) => c.displayName),
        ['A.JPG', 'B.JPG', 'C.JPG'],
      );
    });

    test('a RAW-only card is reported as RAW, not as an empty scan', () {
      final result = IngestDiff.scan(
        candidates: [
          candidate(path: 'DCIM/100CANON/A.CR3', mime: null),
          candidate(path: 'DCIM/100CANON/B.CR3', mime: null),
        ],
        knownSourceRefs: const {},
        scanFolders: const ['DCIM'],
      );
      expect(result.newCandidates, isEmpty);
      expect(result.skippedRaw, 2);
      expect(result.isRawOnly, isTrue);
    });

    test('a card with imported photos is not mistaken for RAW-only', () {
      final known = candidate(path: 'DCIM/A.JPG');
      final result = IngestDiff.scan(
        candidates: [known, candidate(path: 'DCIM/B.CR3', mime: null)],
        knownSourceRefs: {known.sourceRef},
        scanFolders: const ['DCIM'],
      );
      expect(result.isRawOnly, isFalse);
    });
  });

  group('ContentKey', () {
    Uint8List bytes(int n, int fill) =>
        Uint8List.fromList(List<int>.filled(n, fill));

    test('identical samples and size produce the same key', () {
      final a = ContentKey.fromSamples(
        sizeBytes: 100,
        head: bytes(10, 1),
        tail: bytes(10, 2),
      );
      final b = ContentKey.fromSamples(
        sizeBytes: 100,
        head: bytes(10, 1),
        tail: bytes(10, 2),
      );
      expect(a, b);
    });

    test('a different size changes the key even with identical samples', () {
      final a = ContentKey.fromSamples(
        sizeBytes: 100,
        head: bytes(10, 1),
        tail: bytes(10, 2),
      );
      final b = ContentKey.fromSamples(
        sizeBytes: 200,
        head: bytes(10, 1),
        tail: bytes(10, 2),
      );
      expect(a, isNot(b));
    });

    test('different content changes the key', () {
      final a = ContentKey.fromSamples(
        sizeBytes: 100,
        head: bytes(10, 1),
        tail: bytes(10, 2),
      );
      final b = ContentKey.fromSamples(
        sizeBytes: 100,
        head: bytes(10, 9),
        tail: bytes(10, 2),
      );
      expect(a, isNot(b));
    });

    test('compute samples head and tail only', () async {
      final reads = <List<int>>[];
      final key = await ContentKey.compute(
        sizeBytes: 6000000,
        read: (offset, length) async {
          reads.add([offset, length]);
          return bytes(length, 7);
        },
      );
      expect(key, isNotEmpty);
      expect(reads, hasLength(2));
      expect(reads[0], [0, ContentKey.sampleBytes]);
      expect(reads[1], [6000000 - ContentKey.sampleBytes, ContentKey.sampleBytes]);
    });

    test('a file smaller than one sample is read once', () async {
      final reads = <List<int>>[];
      await ContentKey.compute(
        sizeBytes: 1024,
        read: (offset, length) async {
          reads.add([offset, length]);
          return bytes(1024, 3);
        },
      );
      expect(reads, hasLength(1), reason: 'no tail read for a tiny file');
    });
  });
}
