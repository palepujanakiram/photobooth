import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/services/event_pipeline/ingest/folder_ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_diff.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_source.dart';

/// Runs the ingest diff against a **real Canon card** when one is mounted.
///
/// Skipped automatically when no card is present, so it never breaks CI — but on
/// a machine with the reader attached it exercises EXIF parsing, the tier-1 key
/// and the content key against genuine camera files rather than fixtures.
///
/// Point it at another card with:
///   flutter test --dart-define=FZ_CARD=/Volumes/YOUR_CARD
void main() {
  const cardPath = String.fromEnvironment(
    'FZ_CARD',
    defaultValue: '/Volumes/EOS_DIGITAL',
  );
  final card = Directory(cardPath);
  final mounted = card.existsSync();

  group(
    'real Canon card',
    () {
      late FolderIngestSource source;
      late List<IngestCandidate> all;

      setUpAll(() async {
        source = FolderIngestSource(
          directory: card,
          id: 'EOS_DIGITAL',
          sourceKind: MediaSource.sdCard,
        );
        all = await source.listAll();
      });

      test('finds the DCIM photos and nothing else', () {
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        expect(result.hasNew, isTrue);
        for (final c in result.newCandidates) {
          expect(c.folder, startsWith('DCIM/'));
          expect(c.displayName.toUpperCase(), endsWith('.JPG'));
        }
      });

      test('skips Canon CANONMSC sidecars', () {
        // A .CTG sidecar lives inside DCIM, so folder scope alone does not
        // exclude it — the type filter has to.
        final ctg = all.where((c) => c.displayName.toUpperCase().endsWith('.CTG'));
        for (final c in ctg) {
          expect(IngestMimeTypes.isImportable(c), isFalse);
        }
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        expect(
          result.newCandidates.any((c) => c.folder.contains('CANONMSC')),
          isFalse,
        );
      });

      test('reads EXIF capture time from the real headers', () {
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        for (final c in result.newCandidates) {
          expect(c.capturedAtMs, isNotNull);
          final taken = DateTime.fromMillisecondsSinceEpoch(c.capturedAtMs!);
          expect(taken.year, greaterThan(2000));
        }
      });

      test('the tier-1 key carries size and mtime', () {
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        for (final c in result.newCandidates) {
          expect(
            c.sourceRef,
            matches(RegExp(r'^EOS_DIGITAL:DCIM/.+\.JPG:\d+:\d+$')),
          );
          expect(c.sizeBytes, greaterThan(1000000), reason: 'a real 24MP JPEG');
        }
      });

      test('a rescan against known keys imports nothing', () {
        final first = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        final known = first.newCandidates.map((c) => c.sourceRef).toSet();
        final second = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: known,
          scanFolders: const ['DCIM'],
        );
        expect(second.hasNew, isFalse);
        expect(second.alreadyImported, first.newCandidates.length);
        expect(second.isEmptyCard, isFalse);
      });

      test('distinct photos produce distinct content keys', () async {
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        final keys = <String>{};
        for (final c in result.newCandidates) {
          keys.add(
            await ContentKey.compute(
              sizeBytes: c.sizeBytes,
              read: (offset, length) => source.readRange(c, offset, length),
            ),
          );
        }
        expect(keys.length, result.newCandidates.length);
      });

      test('the same photo hashes identically twice', () async {
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        final c = result.newCandidates.first;
        Future<String> key() => ContentKey.compute(
              sizeBytes: c.sizeBytes,
              read: (o, l) => source.readRange(c, o, l),
            );
        expect(await key(), await key());
      });

      test('macOS mount artefacts are ignored', () {
        // Mounting on a Mac writes .fseventsd at the volume root.
        final result = IngestDiff.scan(
          candidates: all,
          knownSourceRefs: const {},
          scanFolders: const ['DCIM'],
        );
        expect(
          result.newCandidates.any((c) => c.relativePath.contains('fseventsd')),
          isFalse,
        );
      });
    },
    skip: mounted ? false : 'No card mounted at $cardPath',
  );
}
