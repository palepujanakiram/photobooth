import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_diff.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_source.dart';

IngestCandidate c({
  String path = 'DCIM/100CANON/IMG_0001.JPG',
  String? name,
  String? mime = 'image/jpeg',
}) {
  final display = name ?? path.split('/').last;
  return IngestCandidate(
    sourceId: 'VOL1',
    relativePath: path,
    displayName: display,
    sizeBytes: 100,
    modifiedAtMs: 1,
    mimeType: mime,
    uri: '/tmp/\$display',
  );
}

void main() {
  IngestScanResult scan(
    List<IngestCandidate> candidates, {
    Set<String> known = const {},
  }) {
    return IngestDiff.scan(
      candidates: candidates,
      knownSourceRefs: known,
      scanFolders: const ['DCIM'],
    );
  }

  group('the three empty outcomes are distinguishable', () {
    test('a freshly formatted card reads as empty, not as all-imported', () {
      // Reporting "all 0 photos have been imported" is nonsense an operator
      // cannot act on.
      final result = scan(const []);
      expect(result.isEmptyCard, isTrue);
      expect(result.isRawOnly, isFalse);
      expect(result.onlyOutsideScope, isFalse);
    });

    test('an imported card is not mistaken for an empty one', () {
      final photo = c();
      final result = scan([photo], known: {photo.sourceRef});
      expect(result.isEmptyCard, isFalse);
      expect(result.alreadyImported, 1);
    });

    test('a RAW-only card is neither empty nor all-imported', () {
      final result = scan([c(path: 'DCIM/A.CR3', mime: null)]);
      expect(result.isRawOnly, isTrue);
      expect(result.isEmptyCard, isFalse);
    });

    test('photos only outside DCIM are reachable, not a dead end', () {
      final result = scan([
        c(path: 'Pictures/a.jpg'),
        c(path: 'Download/b.jpg'),
      ]);
      expect(result.onlyOutsideScope, isTrue);
      expect(result.isEmptyCard, isFalse);
      expect(result.hasNew, isFalse);
      // The operator must be offered these, or the card is unimportable.
      expect(result.widenableFolders.map((f) => f.folder).toSet(),
          {'Pictures', 'Download'});
    });

    test('widenable folders exclude the ones already in scope', () {
      final result = scan([
        c(path: 'DCIM/100CANON/a.jpg'),
        c(path: 'Pictures/b.jpg'),
      ]);
      expect(result.hasNew, isTrue);
      expect(result.onlyOutsideScope, isFalse);
      expect(result.widenableFolders.single.folder, 'Pictures');
    });

    test('a card with only non-image files is not called empty', () {
      final result = scan([c(path: 'DCIM/notes.txt', mime: 'text/plain')]);
      expect(result.isEmptyCard, isFalse);
      expect(result.skippedOtherType, 1);
    });
  });
}
