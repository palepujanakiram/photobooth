import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/logger.dart';
import 'local_kiosk_codec.dart';
import 'local_kiosk_models.dart';

const kKioskDbFileName = 'kiosk.db';
const kKioskLedgerJsonFileName = 'ledger.json';
const kKioskLedgerMigratedSuffix = '.migrated';

const _dbVersion = 1;

/// SQLite persistence for [LocalKioskStore] (v2-1).
///
/// Public store API stays map-shaped in memory; this layer owns WAL + migration
/// from `ledger.json`. Schema includes nullable `event_id` / `share_token` for
/// later v2 slices without a second migration.
class LocalKioskDb {
  LocalKioskDb(this._db);

  final Database _db;

  Database get database => _db;

  static Future<LocalKioskDb?> open(Directory dir) async {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final path = p.join(dir.path, kKioskDbFileName);
      final db = await openDatabase(
        path,
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      );
      return LocalKioskDb(db);
    } catch (e, st) {
      AppLogger.debug('LocalKioskDb.open failed ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE kiosk_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
)''');
    await db.execute('''
CREATE TABLE sessions (
  id TEXT PRIMARY KEY NOT NULL,
  payload_json TEXT NOT NULL,
  kiosk_code TEXT,
  payment_status TEXT,
  event_id TEXT,
  share_token TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE payments (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  receipt_number TEXT
)''');
    await db.execute('''
CREATE TABLE print_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  receipt_number TEXT
)''');
    await db.execute('''
CREATE TABLE receipts (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  receipt_number TEXT
)''');
    await db.execute('''
CREATE TABLE invoice_sequences (
  series TEXT PRIMARY KEY NOT NULL,
  last_value INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE outbox (
  id TEXT PRIMARY KEY NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)''');
    await db.execute(
      'CREATE UNIQUE INDEX outbox_entity_uidx ON outbox(entity_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX outbox_status_idx ON outbox(status, entity_type, created_at_ms)',
    );
    await db.execute('''
CREATE TABLE synced_assets (
  relative_path TEXT PRIMARY KEY NOT NULL,
  synced_at_ms INTEGER NOT NULL
)''');
  }

  Future<void> close() => _db.close();

  Future<bool> isEmpty() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM sessions');
    final sessions = (rows.first['c'] as int?) ?? 0;
    if (sessions > 0) return false;
    final meta = await _db.query('kiosk_meta', limit: 1);
    if (meta.isNotEmpty) return false;
    final outbox = await _db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return ((outbox.first['c'] as int?) ?? 0) == 0;
  }

  /// Import [ledger] in one transaction. Caller renames `ledger.json` after.
  Future<void> importLedger(KioskLedgerData ledger) async {
    await _db.transaction((txn) async {
      await _replaceAllUnlocked(txn, ledger);
    });
  }

  /// Full replace used for durable save of the in-memory ledger snapshot.
  Future<void> replaceAll(KioskLedgerData ledger) async {
    await _db.transaction((txn) async {
      await _replaceAllUnlocked(txn, ledger);
    });
  }

  Future<KioskLedgerData> loadAll() async {
    final sessions = <String, LocalSessionRow>{};
    for (final row in await _db.query('sessions')) {
      final id = row['id']! as String;
      sessions[id] = LocalSessionRow(
        id: id,
        payload: _decodeMap(row['payload_json'] as String?),
        kioskCode: row['kiosk_code'] as String?,
        paymentStatus: row['payment_status'] as String?,
        createdAtMs: row['created_at_ms'] as int,
        updatedAtMs: row['updated_at_ms'] as int,
      );
    }

    Future<Map<String, LocalEntityRow>> loadEntities(String table) async {
      final out = <String, LocalEntityRow>{};
      for (final row in await _db.query(table)) {
        final id = row['id']! as String;
        out[id] = LocalEntityRow(
          id: id,
          sessionId: row['session_id']! as String,
          payload: _decodeMap(row['payload_json'] as String?),
          createdAtMs: row['created_at_ms'] as int,
          receiptNumber: row['receipt_number'] as String?,
        );
      }
      return out;
    }

    final invoiceSequences = <String, int>{};
    for (final row in await _db.query('invoice_sequences')) {
      invoiceSequences[row['series']! as String] = row['last_value'] as int;
    }

    final outbox = <String, KioskOutboxEntry>{};
    for (final row in await _db.query('outbox')) {
      final id = row['id']! as String;
      outbox[id] = KioskOutboxEntry(
        id: id,
        entityType: row['entity_type']! as String,
        entityId: row['entity_id']! as String,
        payload: _decodeMap(row['payload_json'] as String?),
        status: row['status']! as String,
        attempts: row['attempts'] as int,
        createdAtMs: row['created_at_ms'] as int,
        updatedAtMs: row['updated_at_ms'] as int,
      );
    }

    final syncedAssets = <String, int>{};
    for (final row in await _db.query('synced_assets')) {
      syncedAssets[row['relative_path']! as String] =
          row['synced_at_ms'] as int;
    }

    String? currentSessionId;
    final meta = await _db.query(
      'kiosk_meta',
      where: 'key = ?',
      whereArgs: const ['current_session_id'],
      limit: 1,
    );
    if (meta.isNotEmpty) {
      final v = meta.first['value'] as String?;
      if (v != null && v.isNotEmpty) currentSessionId = v;
    }

    final data = KioskLedgerData(
      currentSessionId: currentSessionId,
      sessions: sessions,
      payments: await loadEntities('payments'),
      printJobs: await loadEntities('print_jobs'),
      receipts: await loadEntities('receipts'),
      invoiceSequences: invoiceSequences,
      outbox: outbox,
      syncedAssets: syncedAssets,
    );
    data.recoverInFlightOutbox();
    return data;
  }

  Future<void> _replaceAllUnlocked(
    DatabaseExecutor txn,
    KioskLedgerData ledger,
  ) async {
    await txn.delete('sessions');
    await txn.delete('payments');
    await txn.delete('print_jobs');
    await txn.delete('receipts');
    await txn.delete('invoice_sequences');
    await txn.delete('outbox');
    await txn.delete('synced_assets');
    await txn.delete('kiosk_meta');

    await txn.insert('kiosk_meta', {
      'key': 'schema_version',
      'value': '$_dbVersion',
    });
    final current = ledger.currentSessionId;
    if (current != null && current.isNotEmpty) {
      await txn.insert('kiosk_meta', {
        'key': 'current_session_id',
        'value': current,
      });
    }

    for (final row in ledger.sessions.values) {
      final payload = row.payload;
      await txn.insert('sessions', {
        'id': row.id,
        'payload_json': jsonEncode(payload),
        'kiosk_code': row.kioskCode,
        'payment_status': row.paymentStatus,
        'event_id': payload['eventId']?.toString() ??
            payload['event_id']?.toString(),
        'share_token': payload['shareToken']?.toString() ??
            payload['share_token']?.toString(),
        'created_at_ms': row.createdAtMs,
        'updated_at_ms': row.updatedAtMs,
      });
    }

    Future<void> insertEntities(
      String table,
      Iterable<LocalEntityRow> rows,
    ) async {
      for (final row in rows) {
        await txn.insert(table, {
          'id': row.id,
          'session_id': row.sessionId,
          'payload_json': jsonEncode(row.payload),
          'created_at_ms': row.createdAtMs,
          'receipt_number': row.receiptNumber,
        });
      }
    }

    await insertEntities('payments', ledger.payments.values);
    await insertEntities('print_jobs', ledger.printJobs.values);
    await insertEntities('receipts', ledger.receipts.values);

    for (final e in ledger.invoiceSequences.entries) {
      await txn.insert('invoice_sequences', {
        'series': e.key,
        'last_value': e.value,
      });
    }

    for (final row in ledger.outbox.values) {
      await txn.insert('outbox', {
        'id': row.id,
        'entity_type': row.entityType,
        'entity_id': row.entityId,
        'payload_json': jsonEncode(row.payload),
        'status': row.status,
        'attempts': row.attempts,
        'created_at_ms': row.createdAtMs,
        'updated_at_ms': row.updatedAtMs,
      });
    }

    for (final e in ledger.syncedAssets.entries) {
      await txn.insert('synced_assets', {
        'relative_path': e.key,
        'synced_at_ms': e.value,
      });
    }
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }
}

/// One-shot `ledger.json` → SQLite import. Never deletes JSON on failure.
Future<KioskLedgerData?> tryImportLedgerJson(Directory dir) async {
  final file = File(p.join(dir.path, kKioskLedgerJsonFileName));
  if (!await file.exists()) return null;
  try {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return KioskLedgerData();
    return KioskLedgerData.fromJson(jsonDecode(raw));
  } catch (e, st) {
    AppLogger.debug('LocalKioskDb: ledger.json import read failed ($e)');
    AppLogger.debug('$st');
    return null;
  }
}

Future<void> archiveLedgerJson(Directory dir) async {
  final file = File(p.join(dir.path, kKioskLedgerJsonFileName));
  if (!await file.exists()) return;
  final dest = File(
    p.join(dir.path, '$kKioskLedgerJsonFileName$kKioskLedgerMigratedSuffix'),
  );
  try {
    if (await dest.exists()) {
      await dest.delete();
    }
    await file.rename(dest.path);
  } catch (e, st) {
    AppLogger.debug('LocalKioskDb: archive ledger.json failed ($e)');
    AppLogger.debug('$st');
  }
}
