import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_evp_cols_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a table that predates a column gets it added, once', () async {
    final path = '${dir.path}/legacy.db';
    final db = await databaseFactory.openDatabase(path);
    // The shape a booth in the field already has: no started_at_ms.
    await db.execute('''
CREATE TABLE evp_pipeline_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,
  media_id TEXT NOT NULL,
  event_id TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL)''');

    Future<Set<String>> columns() async => {
          for (final r in await db.rawQuery('PRAGMA table_info(evp_pipeline_jobs)'))
            (r['name'] ?? '').toString(),
        };
    expect(await columns(), isNot(contains('started_at_ms')));

    await EventPipelineDb.createSchema(db);
    expect(await columns(), contains('started_at_ms'));

    // Idempotent: every launch runs this, and ADD COLUMN twice is an error.
    await EventPipelineDb.createSchema(db);
    expect(await columns(), contains('started_at_ms'));
    await db.close();
  });

  test('a fresh database already has the column', () async {
    final db = await databaseFactory.openDatabase('${dir.path}/fresh.db');
    await EventPipelineDb.createSchema(db);
    final columns = {
      for (final r in await db.rawQuery('PRAGMA table_info(evp_pipeline_jobs)'))
        (r['name'] ?? '').toString(),
    };
    expect(columns, contains('started_at_ms'));
    await db.close();
  });
}
