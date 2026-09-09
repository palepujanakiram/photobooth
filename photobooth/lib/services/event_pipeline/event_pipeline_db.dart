import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../utils/logger.dart';
import '../local_kiosk_db.dart' show kKioskDbFileName;
import '../local_kiosk_store.dart' show kKioskDirName;

/// Event pipeline tables, living inside the existing `kiosk.db` file.
///
/// **Deliberately opened without a `version:` argument.** sqflite only runs its
/// `onCreate` / `onUpgrade` machinery for a versioned connection, so omitting it
/// means this connection can never trigger a migration on the kiosk ledger. The
/// schema is then established with `CREATE TABLE IF NOT EXISTS`, which is
/// idempotent on both a fresh and an existing database, on every launch.
///
/// That is why there is no `_dbVersion` bump here. The alternative — versioning
/// the shared file and writing an `onUpgrade` — would put every existing booth's
/// sessions, payments and receipts at risk for no benefit.
///
/// Two properties make sharing the file safe, both already true of the existing
/// code: `LocalKioskDb` enables WAL, so a second connection is fine; and
/// `LocalKioskDb._replaceAllUnlocked` deletes from a **hardcoded table list**,
/// so `replaceAll()` can never reach an `evp_*` table. No `evp_*` table carries a
/// foreign key into a kiosk table either, so `PRAGMA foreign_keys` is a non-issue.
class EventPipelineDb {
  EventPipelineDb(this._db);

  final Database _db;

  Database get database => _db;

  /// Overridable so tests can point at a temp directory.
  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  /// The folder holding the kiosk ledger — **not** the support root.
  ///
  /// Getting this wrong is silent: `open()` happily creates a fresh database
  /// wherever it is pointed, so the pipeline ran for a full import against a
  /// second file at the support root while the real ledger sat untouched in
  /// `fotozen_kiosk/`. Everything worked, which is what made it hard to see.
  static Future<Directory> defaultDirectory() async {
    final root = await supportDirectory();
    final dir = Directory(p.join(root.path, kKioskDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Opens the pipeline connection and ensures the schema exists.
  ///
  /// Returns null rather than throwing when the database is unavailable — a
  /// booth with no writable storage must still boot into the guest flow.
  static Future<EventPipelineDb?> open(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final path = p.join(dir.path, kKioskDbFileName);
      final db = await openDatabase(
        path,
        onConfigure: (db) async {
          // A second writer on the same file can collide with the kiosk ledger's
          // transactions. WAL keeps readers unblocked; the timeout makes a
          // writer wait rather than fail fast with "database is locked".
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        },
      );
      await createSchema(db);
      return EventPipelineDb(db);
    } catch (e, st) {
      AppLogger.debug('EventPipelineDb.open failed ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  static Future<EventPipelineDb?> openDefault() async {
    return open(await defaultDirectory());
  }

  Future<void> close() => _db.close();

  /// Idempotent. Safe to call on every launch, fresh install or upgrade alike.
  @visibleForTesting
  static Future<void> createSchema(Database db) async {
    for (final statement in _schema) {
      await db.execute(statement);
    }
  }

  /// Drops every pipeline table. Tests and an operator "purge event" action.
  @visibleForTesting
  static Future<void> dropSchema(Database db) async {
    for (final table in tableNames) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  static const List<String> tableNames = <String>[
    'evp_media_items',
    'evp_media_renditions',
    'evp_ingest_sources',
    'evp_pipeline_jobs',
    'evp_upload_queue',
    'evp_event_frames',
    'evp_meta',
  ];

  static const List<String> _schema = <String>[
    '''
CREATE TABLE IF NOT EXISTS evp_media_items (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT,
  source TEXT NOT NULL,
  source_ref TEXT NOT NULL,
  content_key TEXT NOT NULL,
  original_filename TEXT,
  captured_at_ms INTEGER,
  original_bytes INTEGER,
  stage TEXT NOT NULL,
  remote_session_id TEXT,
  remote_photo_id TEXT,
  steps_json TEXT,
  step_index INTEGER NOT NULL DEFAULT 0,
  selected_at_ms INTEGER,
  ai_skipped INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)''',
    'CREATE UNIQUE INDEX IF NOT EXISTS evp_media_source_uidx '
        'ON evp_media_items(source, source_ref)',
    'CREATE UNIQUE INDEX IF NOT EXISTS evp_media_content_uidx '
        'ON evp_media_items(content_key)',
    'CREATE INDEX IF NOT EXISTS evp_media_stage_idx '
        'ON evp_media_items(stage, created_at_ms)',
    'CREATE INDEX IF NOT EXISTS evp_media_event_idx '
        'ON evp_media_items(event_id, created_at_ms)',
    '''
CREATE TABLE IF NOT EXISTS evp_media_renditions (
  media_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  path TEXT NOT NULL,
  width INTEGER,
  height INTEGER,
  bytes INTEGER,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY (media_id, kind)
)''',
    '''
CREATE TABLE IF NOT EXISTS evp_ingest_sources (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,
  label TEXT,
  last_seen_at_ms INTEGER,
  last_scan_at_ms INTEGER,
  imported_count INTEGER NOT NULL DEFAULT 0
)''',
    '''
CREATE TABLE IF NOT EXISTS evp_pipeline_jobs (
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
  updated_at_ms INTEGER NOT NULL
)''',
    'CREATE UNIQUE INDEX IF NOT EXISTS evp_jobs_kind_media_uidx '
        'ON evp_pipeline_jobs(kind, media_id)',
    'CREATE INDEX IF NOT EXISTS evp_jobs_ready_idx '
        'ON evp_pipeline_jobs(kind, status, next_attempt_at_ms)',
    '''
CREATE TABLE IF NOT EXISTS evp_upload_queue (
  id TEXT PRIMARY KEY NOT NULL,
  media_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)''',
    'CREATE UNIQUE INDEX IF NOT EXISTS evp_upload_kind_media_uidx '
        'ON evp_upload_queue(kind, media_id)',
    'CREATE INDEX IF NOT EXISTS evp_upload_ready_idx '
        'ON evp_upload_queue(status, next_attempt_at_ms)',
    '''
CREATE TABLE IF NOT EXISTS evp_event_frames (
  id TEXT PRIMARY KEY NOT NULL,
  event_id TEXT NOT NULL,
  name TEXT,
  overlay_url TEXT NOT NULL,
  local_path TEXT,
  width INTEGER,
  height INTEGER,
  downloaded_at_ms INTEGER
)''',
    'CREATE INDEX IF NOT EXISTS evp_frames_event_idx '
        'ON evp_event_frames(event_id)',
    '''
CREATE TABLE IF NOT EXISTS evp_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
)''',
  ];
}
