import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/media_rendition.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_ledger.dart';

void main() {
  late Directory dir;
  late EventPipelineDb db;
  late EventPipelineLedger ledger;
  var clock = 1;
  var ids = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_evp_ledger_');
    clock = 1;
    ids = 0;
    db = (await EventPipelineDb.open(dir))!;
    ledger = EventPipelineLedger(
      db: db,
      nowMs: () => clock++,
      newId: () => 'm${ids++}',
    );
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<MediaInsertResult> insert({
    String source = MediaSource.sdCard,
    String ref = 'vol:DCIM/100CANON/IMG_0001.JPG:100:200',
    String key = 'ck-1',
    String? filename = 'IMG_0001.JPG',
  }) {
    return ledger.insertIfNew(
      source: source,
      sourceRef: ref,
      contentKey: key,
      originalFilename: filename,
      capturedAtMs: 1000,
      originalBytes: 6000000,
    );
  }

  group('dedupe', () {
    test('a first import is new', () async {
      final r = await insert();
      expect(r.isNew, isTrue);
      expect(r.item.stage, MediaStage.ingested);
      expect(r.item.originalFilename, 'IMG_0001.JPG');
    });

    test('rescanning the same card imports nothing', () async {
      await insert();
      final second = await insert();
      expect(second.isNew, isFalse);
      expect(await ledger.listUnselected(), hasLength(1));
    });

    test('a reformatted card re-imports: same path, new size and mtime',
        () async {
      // Canon "auto reset" numbering restarts at IMG_0001 after a format, so the
      // path repeats for a genuinely different photo. Size and mtime are what
      // stop that being silently skipped.
      await insert(ref: 'vol:DCIM/100CANON/IMG_0001.JPG:100:200', key: 'ck-a');
      final reshot = await insert(
        ref: 'vol:DCIM/100CANON/IMG_0001.JPG:812:999',
        key: 'ck-b',
      );
      expect(reshot.isNew, isTrue);
      expect(await ledger.listUnselected(), hasLength(2));
    });

    test('the same photo by two routes lands once', () async {
      final tethered = await insert(source: MediaSource.ptp, ref: 'ptp:1');
      final fromCard = await insert(
        source: MediaSource.sdCard,
        ref: 'vol:DCIM/IMG_9.JPG:1:2',
      );
      expect(tethered.isNew, isTrue);
      expect(fromCard.isNew, isFalse, reason: 'content key already known');
      expect(fromCard.item.id, tethered.item.id);
    });

    test('knownSourceRefs returns tier-1 keys for one source only', () async {
      await insert(ref: 'refA', key: 'ck-a');
      await insert(source: MediaSource.gallery, ref: 'refB', key: 'ck-b');
      expect(await ledger.knownSourceRefs(MediaSource.sdCard), {'refA'});
    });
  });

  group('selection and steps', () {
    test('markSelected freezes the chain and moves to QUEUED', () async {
      final r = await insert();
      final selected =
          await ledger.markSelected(r.item.id, const ['ai', 'frame', 'print']);
      expect(selected!.steps, ['ai', 'frame', 'print']);
      expect(selected.stepIndex, 0);
      expect(selected.stage, MediaStage.queued);
      expect(selected.isSelected, isTrue);
    });

    test('an empty chain completes on selection', () async {
      final r = await insert();
      final selected = await ledger.markSelected(r.item.id, const []);
      expect(selected!.stage, MediaStage.done);
    });

    test('a frozen chain survives a read back through the database', () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai', 'print']);
      final reloaded = await ledger.findById(r.item.id);
      expect(reloaded!.steps, ['ai', 'print']);
      expect(reloaded.currentStep, 'ai');
    });

    test('advanceStep walks the chain and derives each stage', () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai', 'frame', 'print']);
      expect((await ledger.advanceStep(r.item.id))!.stage, MediaStage.framing);
      expect((await ledger.advanceStep(r.item.id))!.stage, MediaStage.printing);
      final done = await ledger.advanceStep(r.item.id);
      expect(done!.stage, MediaStage.done);
      expect(done.isChainComplete, isTrue);
    });
  });

  group('skipAi', () {
    test('drops ai and resumes at frame', () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai', 'frame', 'print']);
      final skipped = await ledger.skipAi(
        r.item.id,
        newSteps: const ['frame', 'print'],
      );
      expect(skipped!.steps, ['frame', 'print']);
      expect(skipped.stepIndex, 0);
      expect(skipped.stage, MediaStage.framing);
      expect(skipped.aiSkipped, isTrue);
    });

    test('does not re-run steps already completed', () async {
      // A bulk Skip AI can land on items that already got past AI and framing.
      // Those must resume where they were, not re-run framing.
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai', 'frame', 'print']);
      await ledger.advanceStep(r.item.id); // ai done, on frame
      await ledger.advanceStep(r.item.id); // frame done, on print
      final skipped = await ledger.skipAi(
        r.item.id,
        newSteps: const ['frame', 'print'],
      );
      expect(
        skipped!.stepIndex,
        1,
        reason: 'frame already done, resume at print',
      );
      expect(skipped.stage, MediaStage.printing);
    });

    test('an item mid-frame stays on frame rather than jumping back', () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai', 'frame', 'print']);
      await ledger.advanceStep(r.item.id); // ai done, on frame
      final skipped = await ledger.skipAi(
        r.item.id,
        newSteps: const ['frame', 'print'],
      );
      expect(skipped!.stepIndex, 0);
      expect(skipped.stage, MediaStage.framing);
    });

    test('a chain is stored in canonical order regardless of input order',
        () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['print', 'ai', 'frame']);
      final reloaded = await ledger.findById(r.item.id);
      expect(reloaded!.steps, ['ai', 'frame', 'print']);
    });

    test('an ai-only chain completes', () async {
      final r = await insert();
      await ledger.markSelected(r.item.id, const ['ai']);
      final skipped = await ledger.skipAi(r.item.id, newSteps: const []);
      expect(skipped!.stage, MediaStage.done);
      expect(skipped.aiSkipped, isTrue);
    });
  });

  group('renditions', () {
    test('print picks framed over ai over source', () async {
      final r = await insert();
      final id = r.item.id;
      await ledger.putRendition(MediaRendition(
        mediaId: id,
        kind: RenditionKind.source,
        path: 'a/src.jpg',
        createdAtMs: 1,
      ));
      expect((await ledger.bestRenditionForPrint(id))!.kind,
          RenditionKind.source);

      await ledger.putRendition(MediaRendition(
        mediaId: id,
        kind: RenditionKind.ai,
        path: 'a/ai.jpg',
        createdAtMs: 2,
      ));
      expect((await ledger.bestRenditionForPrint(id))!.kind, RenditionKind.ai);

      await ledger.putRendition(MediaRendition(
        mediaId: id,
        kind: RenditionKind.framed,
        path: 'a/framed.jpg',
        createdAtMs: 3,
      ));
      expect(
        (await ledger.bestRenditionForPrint(id))!.kind,
        RenditionKind.framed,
      );
    });

    test('a failed frame step still prints the ai result', () async {
      final r = await insert();
      await ledger.putRendition(MediaRendition(
        mediaId: r.item.id,
        kind: RenditionKind.source,
        path: 'src.jpg',
        createdAtMs: 1,
      ));
      await ledger.putRendition(MediaRendition(
        mediaId: r.item.id,
        kind: RenditionKind.ai,
        path: 'ai.jpg',
        createdAtMs: 2,
      ));
      final best = await ledger.bestRenditionForPrint(r.item.id);
      expect(best!.kind, RenditionKind.ai);
    });

    test('re-storing a rendition kind replaces it', () async {
      final r = await insert();
      for (final path in ['first.jpg', 'second.jpg']) {
        await ledger.putRendition(MediaRendition(
          mediaId: r.item.id,
          kind: RenditionKind.ai,
          path: path,
          createdAtMs: 1,
        ));
      }
      final all = await ledger.renditionsFor(r.item.id);
      expect(all, hasLength(1));
      expect(all.first.path, 'second.jpg');
    });

    test('nothing stored yields no print candidate', () async {
      final r = await insert();
      expect(await ledger.bestRenditionForPrint(r.item.id), isNull);
    });
  });

  group('reads', () {
    test('stageCounts groups by stage', () async {
      final a = await insert(ref: 'r1', key: 'k1');
      final b = await insert(ref: 'r2', key: 'k2');
      await insert(ref: 'r3', key: 'k3');
      await ledger.markSelected(a.item.id, const ['print']);
      await ledger.markSelected(b.item.id, const ['print']);
      final counts = await ledger.stageCounts();
      expect(counts[MediaStage.queued], 2);
      expect(counts[MediaStage.ingested], 1);
    });

    test('listUnselected excludes items already queued', () async {
      final a = await insert(ref: 'r1', key: 'k1');
      await insert(ref: 'r2', key: 'k2');
      await ledger.markSelected(a.item.id, const ['print']);
      expect(await ledger.listUnselected(), hasLength(1));
    });

    test('setRemoteIds records what the ai step waits on', () async {
      final r = await insert();
      await ledger.setRemoteIds(r.item.id, sessionId: 'sess-1');
      final reloaded = await ledger.findById(r.item.id);
      expect(reloaded!.remoteSessionId, 'sess-1');
      expect(reloaded.remotePhotoId, isNull);
    });

    test('setStage records a terminal failure with its reason', () async {
      final r = await insert();
      await ledger.setStage(r.item.id, MediaStage.failed, error: 'no printer');
      final reloaded = await ledger.findById(r.item.id);
      expect(reloaded!.stage, MediaStage.failed);
      expect(reloaded.lastError, 'no printer');
    });
  });

  group('deleteItem', () {
    test('the photo becomes unknown again, so a rescan re-imports it',
        () async {
      final r = await insert();
      expect(await ledger.knownSourceRefs(MediaSource.sdCard), hasLength(1));

      await ledger.deleteItem(r.item.id);

      expect(await ledger.findById(r.item.id), isNull);
      expect(await ledger.knownSourceRefs(MediaSource.sdCard), isEmpty,
          reason: 'a surviving key would report the photo already imported');
      expect((await insert()).isNew, isTrue);
    });

    test('renditions go with the row rather than being orphaned', () async {
      final r = await insert();
      await ledger.putRendition(MediaRendition(
        mediaId: r.item.id,
        kind: RenditionKind.source,
        path: 'src/${r.item.id}.jpg',
        width: 2880,
        height: 1920,
        bytes: 500000,
        createdAtMs: 1,
      ));

      await ledger.deleteItem(r.item.id);

      expect(await ledger.renditionsFor(r.item.id), isEmpty);
    });

    test('deleting an unknown id is harmless', () async {
      await ledger.deleteItem('nope');
      expect(await ledger.findById('nope'), isNull);
    });
  });

  group('shared ledger align', () {
    test('listUpdatedSince returns only newer rows', () async {
      final first = await insert();
      clock = 50;
      await ledger.markSelected(first.item.id, const ['print']);
      final changed = await ledger.listUpdatedSince(0);
      expect(changed, isNotEmpty);
      expect(await ledger.listUpdatedSince(1000), isEmpty);
    });

    test('upsertFromRemote keeps the newer copy', () async {
      final local = await insert();
      final older = MediaItem(
        id: local.item.id,
        source: local.item.source,
        sourceRef: local.item.sourceRef,
        contentKey: local.item.contentKey,
        stage: MediaStage.done,
        createdAtMs: local.item.createdAtMs,
        updatedAtMs: 0,
      );
      await ledger.upsertFromRemote(older);
      expect((await ledger.findById(local.item.id))!.stage, isNot(MediaStage.done));

      final newer = MediaItem(
        id: local.item.id,
        source: local.item.source,
        sourceRef: local.item.sourceRef,
        contentKey: local.item.contentKey,
        stage: MediaStage.done,
        createdAtMs: local.item.createdAtMs,
        updatedAtMs: 9999,
      );
      await ledger.upsertFromRemote(newer);
      expect((await ledger.findById(local.item.id))!.stage, MediaStage.done);
    });

    test('upsertFromRemote ignores a blank id', () async {
      await ledger.upsertFromRemote(const MediaItem(
        id: '  ',
        source: MediaSource.ptp,
        sourceRef: 'x',
        contentKey: 'y',
        stage: MediaStage.ingested,
        createdAtMs: 1,
        updatedAtMs: 1,
      ));
      expect(await ledger.findById('  '), isNull);
    });
  });
}
