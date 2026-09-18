import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/local_kiosk_db.dart';

import 'package:sqflite/sqflite.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_evp_db_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Set<String>> tablesIn(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return {for (final r in rows) (r['name'] ?? '').toString()};
  }

  test('creates every pipeline table on a fresh database', () async {
    final evp = await EventPipelineDb.open(dir);
    expect(evp, isNotNull);
    final tables = await tablesIn(evp!.database);
    for (final name in EventPipelineDb.tableNames) {
      expect(tables, contains(name), reason: '$name should exist');
    }
    await evp.close();
  });

  test('open is idempotent — a second open does not fail or duplicate',
      () async {
    final first = await EventPipelineDb.open(dir);
    await first!.close();
    final second = await EventPipelineDb.open(dir);
    expect(second, isNotNull);
    final tables = await tablesIn(second!.database);
    expect(tables, containsAll(EventPipelineDb.tableNames));
    await second.close();
  });

  test('creating the schema twice on one connection is safe', () async {
    final evp = await EventPipelineDb.open(dir);
    await EventPipelineDb.createSchema(evp!.database);
    await EventPipelineDb.createSchema(evp.database);
    final tables = await tablesIn(evp.database);
    expect(tables, containsAll(EventPipelineDb.tableNames));
    await evp.close();
  });

  Future<void> insertKioskSession(Database db, String id) {
    return db.insert('sessions', {
      'id': id,
      'payload_json': '{"id":"$id"}',
      'kiosk_code': 'K1',
      'created_at_ms': 1,
      'updated_at_ms': 1,
    });
  }

  Future<void> insertMediaItem(Database db, String id, String ref, String ck) {
    return db.insert('evp_media_items', {
      'id': id,
      'source': 'sdcard',
      'source_ref': ref,
      'content_key': ck,
      'stage': 'INGESTED',
      'step_index': 0,
      'ai_skipped': 0,
      'created_at_ms': 1,
      'updated_at_ms': 1,
    });
  }

  test('opens alongside an existing v1 kiosk ledger without migrating it',
      () async {
    // A booth already carrying real ledger data.
    final kiosk = await LocalKioskDb.open(dir);
    expect(kiosk, isNotNull);
    await insertKioskSession(kiosk!.database, 's1');

    final evp = await EventPipelineDb.open(dir);
    expect(evp, isNotNull);

    // Kiosk rows survive, and the schema version stamp is untouched — proof our
    // unversioned connection cannot have triggered onCreate or onUpgrade.
    final sessions = await kiosk.database.query('sessions');
    expect(sessions, hasLength(1));
    final version = await evp!.database.rawQuery('PRAGMA user_version');
    expect(version.first.values.first, 1);

    await evp.close();
    await kiosk.close();
  });

  test('the kiosk ledger wipe cannot reach evp_ tables', () async {
    final kiosk = await LocalKioskDb.open(dir);
    final evp = await EventPipelineDb.open(dir);

    await evp!.database.insert('evp_meta', {'key': 'k', 'value': 'v'});
    await insertMediaItem(evp.database, 'm1', 'vol:DCIM/a.jpg:1:2', 'ck1');
    await insertKioskSession(kiosk!.database, 's1');

    // Exactly what LocalKioskDb._replaceAllUnlocked does on every mutation: a
    // delete across its hardcoded table list, which does not include evp_*.
    for (final table in const [
      'sessions',
      'payments',
      'print_jobs',
      'receipts',
      'invoice_sequences',
      'outbox',
      'synced_assets',
      'kiosk_meta',
    ]) {
      await kiosk.database.delete(table);
    }

    expect(await kiosk.database.query('sessions'), isEmpty);
    expect(await evp.database.query('evp_meta'), hasLength(1));
    expect(await evp.database.query('evp_media_items'), hasLength(1));

    await evp.close();
    await kiosk.close();
  });

  test('unique indexes enforce both dedupe tiers', () async {
    final evp = await EventPipelineDb.open(dir);
    Map<String, Object?> row(String id, String ref, String ck) => {
          'id': id,
          'source': 'sdcard',
          'source_ref': ref,
          'content_key': ck,
          'stage': 'INGESTED',
          'step_index': 0,
          'ai_skipped': 0,
          'created_at_ms': 1,
          'updated_at_ms': 1,
        };

    await evp!.database.insert('evp_media_items', row('m1', 'refA', 'ckA'));

    // Tier 1: same (source, source_ref).
    await expectLater(
      evp.database.insert('evp_media_items', row('m2', 'refA', 'ckB')),
      throwsA(isA<DatabaseException>()),
    );
    // Tier 2: same content_key by a different route.
    await expectLater(
      evp.database.insert('evp_media_items', row('m3', 'refB', 'ckA')),
      throwsA(isA<DatabaseException>()),
    );
    // Genuinely different on both keys.
    await evp.database.insert('evp_media_items', row('m4', 'refB', 'ckB'));
    expect(await evp.database.query('evp_media_items'), hasLength(2));

    await evp.close();
  });

  test('dropSchema removes the pipeline tables only', () async {
    final kiosk = await LocalKioskDb.open(dir);
    final evp = await EventPipelineDb.open(dir);
    await EventPipelineDb.dropSchema(evp!.database);
    final tables = await tablesIn(evp.database);
    for (final name in EventPipelineDb.tableNames) {
      expect(tables, isNot(contains(name)));
    }
    expect(tables, contains('sessions'));
    await evp.close();
    await kiosk!.close();
  });
}
