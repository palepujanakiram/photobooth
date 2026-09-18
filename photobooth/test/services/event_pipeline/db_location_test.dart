import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photobooth/services/event_pipeline/event_pipeline_db.dart';
import 'package:photobooth/services/local_kiosk_db.dart';
import 'package:photobooth/services/local_kiosk_store.dart';

/// The pipeline must open the **same file** as the kiosk ledger.
///
/// Every other DB test injects a temp directory into both, so they agreed by
/// construction and proved nothing about the real path. On device they diverged:
/// the ledger lived in `{support}/fotozen_kiosk/kiosk.db` while the pipeline
/// created its own at `{support}/kiosk.db`. A full import ran against the wrong
/// file and looked completely healthy, which is what made it invisible.
void main() {
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('fz_evp_loc_');
    LocalKioskStore.supportDirectory = () async => support;
    EventPipelineDb.supportDirectory = () async => support;
  });

  tearDown(() async {
    LocalKioskStore.supportDirectory = getApplicationSupportDirectoryStub;
    EventPipelineDb.supportDirectory = getApplicationSupportDirectoryStub;
    if (await support.exists()) await support.delete(recursive: true);
  });

  test('the pipeline resolves to the kiosk ledger folder', () async {
    final dir = await EventPipelineDb.defaultDirectory();
    expect(p.basename(dir.path), kKioskDirName);
    expect(dir.path, p.join(support.path, kKioskDirName));
  });

  test('both open the identical database file', () async {
    final store = LocalKioskStore();
    await store.ensureReady();
    addTearDown(store.closeForTest);

    final evp = await EventPipelineDb.openDefault();
    addTearDown(() async => evp?.close());

    expect(evp, isNotNull);
    expect(
      evp!.database.path,
      store.debugDbPath,
      reason: 'a second file would silently work while sharing nothing',
    );
  });

  test('the pipeline tables land beside the kiosk tables', () async {
    final store = LocalKioskStore();
    await store.ensureReady();
    addTearDown(store.closeForTest);

    final evp = await EventPipelineDb.openDefault();
    addTearDown(() async => evp?.close());

    final tables = await evp!.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = {for (final r in tables) (r['name'] ?? '').toString()};
    // Both families in one file is the whole point of the shared-connection
    // design; either alone means the wrong file was opened.
    expect(names, containsAll(EventPipelineDb.tableNames));
    expect(names, contains('sessions'));
  });

  test('only one kiosk.db exists under the support directory', () async {
    final store = LocalKioskStore();
    await store.ensureReady();
    addTearDown(store.closeForTest);
    final evp = await EventPipelineDb.openDefault();
    addTearDown(() async => evp?.close());

    final found = <String>[];
    await for (final entity in support.list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == kKioskDbFileName) {
        found.add(entity.path);
      }
    }
    expect(found, hasLength(1), reason: 'found: $found');
  });
}

/// Restores the production resolver without importing path_provider here.
Future<Directory> getApplicationSupportDirectoryStub() async {
  throw UnsupportedError('not used in tests');
}
