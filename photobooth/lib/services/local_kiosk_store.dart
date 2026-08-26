import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../utils/local_invoice_number.dart';
import '../utils/logger.dart';
import 'local_kiosk_codec.dart';
import 'local_kiosk_models.dart';
import 'local_session_skeleton.dart';

const _ledgerFileName = 'ledger.json';
const _kioskDirName = 'fotozen_kiosk';
const _emptyIdMessage = 'id must not be empty';

enum _LedgerTable { payments, printJobs, receipts }

/// On-device kiosk ledger: sessions, payments, prints, receipts, outbox,
/// invoice sequences. File-backed (SQLite-shaped tables) so the 4GB TV APK
/// owns guest records without Fly.
class LocalKioskStore {
  LocalKioskStore({
    Future<Directory> Function()? resolveDirectory,
    String Function()? newId,
    int Function()? nowMs,
  })  : _resolveDirectory = resolveDirectory ?? _defaultDirectory,
        _newId = newId ?? _defaultNewId,
        _nowMs = nowMs ?? _defaultNowMs;

  final Future<Directory> Function() _resolveDirectory;
  final String Function() _newId;
  final int Function() _nowMs;

  static LocalKioskStore? instance;

  KioskLedgerData _data = KioskLedgerData();
  bool _ready = false;
  Future<void> _chain = Future<void>.value();

  @visibleForTesting
  static Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory;

  static Future<Directory> _defaultDirectory() async {
    final root = await supportDirectory();
    final dir = Directory(p.join(root.path, _kioskDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _defaultNewId() => const Uuid().v4();

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  static Future<LocalKioskStore> init({
    Future<Directory> Function()? resolveDirectory,
  }) async {
    final store = LocalKioskStore(resolveDirectory: resolveDirectory);
    await store.ensureReady();
    instance = store;
    return store;
  }

  @visibleForTesting
  static void resetInstance() {
    instance = null;
  }

  Future<void> ensureReady() => _serialized(() async {
        if (_ready) return;
        await _loadUnlocked();
        _ready = true;
      });

  Future<void> upsertSession(LocalSessionWrite write) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      _upsertSessionUnlocked(write);
      await _saveUnlocked();
    });
  }

  Future<Map<String, dynamic>?> getSession(String id) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return _data.sessions[id]?.payload;
    });
  }

  Future<LocalEntityRow?> findReceiptForSession(String sessionId) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final sid = sessionId.trim();
      if (sid.isEmpty) return null;
      for (final row in _data.receipts.values) {
        if (row.sessionId == sid) return row;
      }
      return null;
    });
  }

  Future<List<LocalEntityRow>> paymentsForSession(String sessionId) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final sid = sessionId.trim();
      if (sid.isEmpty) return const <LocalEntityRow>[];
      return _data.payments.values.where((e) => e.sessionId == sid).toList();
    });
  }

  Future<File?> saveReceiptPdf(String id, List<int> bytes) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return _writeReceiptPdfUnlocked(id, bytes);
    });
  }

  Future<Map<String, dynamic>?> currentSessionJson() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final id = _data.currentSessionId;
      if (id == null || id.isEmpty) return null;
      return _data.sessions[id]?.payload;
    });
  }

  Future<void> clearCurrentSession() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      _data.currentSessionId = null;
      await _saveUnlocked();
    });
  }

  Future<void> upsertPayment({
    required String id,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) {
    return _upsertEntity(
      kind: _LedgerTable.payments,
      entityType: KioskOutboxEntity.payment,
      id: id,
      sessionId: sessionId,
      payload: payload,
    );
  }

  Future<void> upsertPrintJob({
    required String id,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) {
    return _upsertEntity(
      kind: _LedgerTable.printJobs,
      entityType: KioskOutboxEntity.printJob,
      id: id,
      sessionId: sessionId,
      payload: payload,
    );
  }

  Future<void> upsertReceipt({
    required String id,
    required String sessionId,
    required String receiptNumber,
    required Map<String, dynamic> payload,
  }) {
    return _upsertEntity(
      kind: _LedgerTable.receipts,
      entityType: KioskOutboxEntity.receipt,
      id: id,
      sessionId: sessionId,
      payload: payload,
      receiptNumber: receiptNumber,
    );
  }

  Future<String> allocateInvoiceNumber({
    required String kioskCode,
    DateTime? at,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final date = at ?? DateTime.now();
      final key = receiptSeriesKey(kioskCode, date);
      final next = (_data.invoiceSequences[key] ?? 0) + 1;
      _data.invoiceSequences[key] = next;
      await _saveUnlocked();
      return formatInvoiceNumber(
        kioskCode,
        indianFinancialYearCode(date),
        next,
      );
    });
  }

  /// Raise the local series high-water so the next allocate cannot collide
  /// with numbers already used on Fly (or on a prior install of this booth).
  Future<void> ensureInvoiceSequenceAtLeast({
    required String kioskCode,
    required int lastSeq,
    DateTime? at,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      if (lastSeq < 1) return;
      final key = receiptSeriesKey(kioskCode, at ?? DateTime.now());
      final current = _data.invoiceSequences[key] ?? 0;
      if (lastSeq <= current) return;
      _data.invoiceSequences[key] = lastSeq;
      await _saveUnlocked();
    });
  }

  /// After Fly 409 receipt-number conflict: bump past the colliding number and
  /// rewrite the local receipt + outbox payload so Sync can retry.
  Future<KioskOutboxEntry?> remintReceiptInvoiceNumber({
    required String receiptId,
    required String kioskCode,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final id = receiptId.trim();
      if (id.isEmpty) return null;
      final row = _data.receipts[id];
      if (row == null) return null;

      final oldNumber = parseKioskReceiptNumber(
            row.receiptNumber ?? row.payload['receiptNumber']?.toString(),
          ) ??
          '';
      final parts = parseKioskInvoiceNumberParts(oldNumber);
      if (parts != null) {
        final key = '${parts.booth}/${parts.fy}';
        final current = _data.invoiceSequences[key] ?? 0;
        if (parts.seq > current) {
          _data.invoiceSequences[key] = parts.seq;
        }
      }

      final date = DateTime.now();
      final key = receiptSeriesKey(kioskCode, date);
      final next = (_data.invoiceSequences[key] ?? 0) + 1;
      _data.invoiceSequences[key] = next;
      final number = formatInvoiceNumber(
        kioskCode,
        indianFinancialYearCode(date),
        next,
      );

      final payload = Map<String, dynamic>.from(row.payload)
        ..['receiptNumber'] = number
        ..['id'] = id
        ..['sessionId'] = row.sessionId;
      _data.receipts[id] = LocalEntityRow(
        id: id,
        sessionId: row.sessionId,
        payload: payload,
        createdAtMs: row.createdAtMs,
        receiptNumber: number,
      );

      final existing = _outboxFor(KioskOutboxEntity.receipt, id);
      final now = _nowMs();
      final outbox = KioskOutboxEntry(
        id: existing?.id ?? _newId(),
        entityType: KioskOutboxEntity.receipt,
        entityId: id,
        payload: _data.receipts[id]!.toJson(),
        status: KioskOutboxStatus.pending,
        attempts: 0,
        createdAtMs: existing?.createdAtMs ?? now,
        updatedAtMs: now,
      );
      _data.outbox[outbox.id] = outbox;
      await _saveUnlocked();
      return outbox;
    });
  }

  Future<KioskOutboxEntry> enqueueOutbox({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final row = _enqueueUnlocked(
        entityType: entityType,
        entityId: entityId,
        payload: payload,
      );
      await _saveUnlocked();
      return row;
    });
  }

  Future<List<KioskOutboxEntry>> claimPendingOutbox({int limit = 10}) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final n = limit < 1 ? 0 : limit;
      final pending = _data.outbox.values
          .where((e) => e.status == KioskOutboxStatus.pending)
          .toList()
        ..sort(KioskOutboxEntity.compare);
      final claimed = <KioskOutboxEntry>[];
      for (final row in pending.take(n)) {
        final next = row.copyWith(
          status: KioskOutboxStatus.syncing,
          updatedAtMs: _nowMs(),
        );
        _data.outbox[row.id] = next;
        claimed.add(next);
      }
      if (claimed.isNotEmpty) await _saveUnlocked();
      return claimed;
    });
  }

  Future<void> markOutboxDone(String id) {
    return _markOutbox(id, done: true);
  }

  Future<void> markOutboxFailed(String id, {int maxAttempts = 8}) {
    return _markOutbox(id, done: false, maxAttempts: maxAttempts);
  }

  Future<List<KioskOutboxEntry>> pendingOutbox() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return _data.outbox.values
          .where((e) => e.status == KioskOutboxStatus.pending)
          .toList();
    });
  }

  /// Counts rows that still need a successful Fly ingest.
  Future<KioskOutboxSyncCounts> outboxSyncCounts() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      var pending = 0;
      var syncing = 0;
      var failed = 0;
      for (final row in _data.outbox.values) {
        switch (row.status) {
          case KioskOutboxStatus.pending:
            pending++;
            break;
          case KioskOutboxStatus.syncing:
            syncing++;
            break;
          case KioskOutboxStatus.failed:
            failed++;
            break;
        }
      }
      return KioskOutboxSyncCounts(
        pending: pending,
        syncing: syncing,
        failed: failed,
      );
    });
  }

  /// Manual Sync: put FAILED (and stuck SYNCING) back into PENDING.
  Future<int> requeueOpenOutbox() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      var n = 0;
      final now = _nowMs();
      for (final entry in _data.outbox.entries) {
        final row = entry.value;
        if (row.status != KioskOutboxStatus.failed &&
            row.status != KioskOutboxStatus.syncing) {
          continue;
        }
        _data.outbox[entry.key] = row.copyWith(
          status: KioskOutboxStatus.pending,
          attempts: 0,
          updatedAtMs: now,
        );
        n++;
      }
      if (n > 0) await _saveUnlocked();
      return n;
    });
  }

  Future<KioskOutboxEntry?> findOutbox(String entityType, String entityId) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return _outboxFor(entityType, entityId);
    });
  }

  Future<Map<String, int>> syncedAssets() {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return Map<String, int>.from(_data.syncedAssets);
    });
  }

  Future<void> markAssetSynced(String relativePath, {int? atMs}) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final path = relativePath.trim();
      if (path.isEmpty) return;
      _data.syncedAssets[path] = atMs ?? _nowMs();
      await _saveUnlocked();
    });
  }

  Future<void> unmarkAssetSynced(String relativePath) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      _data.syncedAssets.remove(relativePath.trim());
      await _saveUnlocked();
    });
  }

  Future<LocalDayCounts> countsForDay(DateTime day) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return LocalDayCounts(
        sessions: _countDay(_data.sessions.values.map((e) => e.createdAtMs), day),
        payments: _countDay(_data.payments.values.map((e) => e.createdAtMs), day),
        printJobs:
            _countDay(_data.printJobs.values.map((e) => e.createdAtMs), day),
        receipts: _countDay(_data.receipts.values.map((e) => e.createdAtMs), day),
      );
    });
  }

  Future<List<LocalEntityRow>> paymentsOnDay(DateTime day) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      return _data.payments.values
          .where((e) => _isSameLocalDay(e.createdAtMs, day))
          .toList(growable: false);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await action());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<void> _ensureReadyUnlocked() async {
    if (_ready) return;
    await _loadUnlocked();
    _ready = true;
  }

  void _upsertSessionUnlocked(LocalSessionWrite write) {
    final id = write.id.trim();
    if (id.isEmpty) {
      throw ArgumentError(_emptyIdMessage);
    }
    final now = _nowMs();
    final existing = _data.sessions[id];
    _data.sessions[id] = LocalSessionRow(
      id: id,
      payload: slimSessionPayload(write.payload),
      kioskCode: write.kioskCode ?? existing?.kioskCode,
      paymentStatus: write.paymentStatus ?? existing?.paymentStatus,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    if (write.setCurrent) {
      _data.currentSessionId = id;
    }
    if (write.enqueueOutbox) {
      _enqueueUnlocked(
        entityType: KioskOutboxEntity.session,
        entityId: id,
        payload: _data.sessions[id]!.payload,
      );
    }
  }

  Future<void> _upsertEntity({
    required _LedgerTable kind,
    required String entityType,
    required String id,
    required String sessionId,
    required Map<String, dynamic> payload,
    String? receiptNumber,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final trimmed = id.trim();
      if (trimmed.isEmpty) {
        throw ArgumentError(_emptyIdMessage);
      }
      final table = _table(kind);
      final now = _nowMs();
      final existing = table[trimmed];
      final createdAtMs = existing?.createdAtMs ?? now;
      final storedReceipt = receiptNumber ?? existing?.receiptNumber;
      table[trimmed] = LocalEntityRow(
        id: trimmed,
        sessionId: sessionId,
        payload: Map<String, dynamic>.from(payload),
        createdAtMs: createdAtMs,
        receiptNumber: storedReceipt,
      );
      _enqueueUnlocked(
        entityType: entityType,
        entityId: trimmed,
        payload: table[trimmed]!.toJson(),
      );
      await _saveUnlocked();
    });
  }

  Map<String, LocalEntityRow> _table(_LedgerTable kind) {
    switch (kind) {
      case _LedgerTable.payments:
        return _data.payments;
      case _LedgerTable.printJobs:
        return _data.printJobs;
      case _LedgerTable.receipts:
        return _data.receipts;
    }
  }

  KioskOutboxEntry _enqueueUnlocked({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) {
    if (!KioskOutboxEntity.all.contains(entityType)) {
      throw ArgumentError('unknown entity type');
    }
    if (entityId.trim().isEmpty) {
      throw ArgumentError(_emptyIdMessage);
    }
    final existing = _outboxFor(entityType, entityId);
    final now = _nowMs();
    final row = KioskOutboxEntry(
      id: existing?.id ?? _newId(),
      entityType: entityType,
      entityId: entityId,
      payload: Map<String, dynamic>.from(payload),
      status: KioskOutboxStatus.pending,
      attempts: 0,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
    );
    _data.outbox[row.id] = row;
    return row;
  }

  KioskOutboxEntry? _outboxFor(String entityType, String entityId) {
    for (final row in _data.outbox.values) {
      if (row.entityType == entityType && row.entityId == entityId) {
        return row;
      }
    }
    return null;
  }

  Future<void> _markOutbox(
    String id, {
    required bool done,
    int maxAttempts = 8,
  }) {
    return _serialized(() async {
      await _ensureReadyUnlocked();
      final row = _data.outbox[id];
      if (row == null) return;
      if (done) {
        _data.outbox[id] = row.copyWith(
          status: KioskOutboxStatus.done,
          updatedAtMs: _nowMs(),
        );
      } else {
        final attempts = row.attempts + 1;
        final failed = attempts >= maxAttempts;
        _data.outbox[id] = row.copyWith(
          status:
              failed ? KioskOutboxStatus.failed : KioskOutboxStatus.pending,
          attempts: attempts,
          updatedAtMs: _nowMs(),
        );
      }
      await _saveUnlocked();
    });
  }

  int _countDay(Iterable<int> stamps, DateTime day) {
    var n = 0;
    for (final ms in stamps) {
      if (_isSameLocalDay(ms, day)) n++;
    }
    return n;
  }

  bool _isSameLocalDay(int ms, DateTime day) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }

  Future<File?> _ledgerFile() async {
    try {
      final dir = await _resolveDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File(p.join(dir.path, _ledgerFileName));
    } catch (e, st) {
      AppLogger.debug('LocalKioskStore: directory unavailable ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<File?> _writeReceiptPdfUnlocked(String id, List<int> bytes) async {
    final safe = id.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
    if (safe.isEmpty) return null;
    try {
      final dir = await _resolveDirectory();
      final pdfDir = Directory(p.join(dir.path, 'receipts'));
      if (!await pdfDir.exists()) {
        await pdfDir.create(recursive: true);
      }
      final file = File(p.join(pdfDir.path, '$safe.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      AppLogger.debug('LocalKioskStore: receipt pdf write failed ($e)');
      AppLogger.debug('$st');
      return null;
    }
  }

  Future<void> _loadUnlocked() async {
    final file = await _ledgerFile();
    if (file == null || !await file.exists()) {
      _data = KioskLedgerData();
      return;
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _data = KioskLedgerData();
        return;
      }
      _data = KioskLedgerData.fromJson(jsonDecode(raw));
      _data.recoverInFlightOutbox();
    } catch (e, st) {
      AppLogger.debug('LocalKioskStore: load failed ($e)');
      AppLogger.debug('$st');
      _data = KioskLedgerData();
    }
  }

  Future<void> _saveUnlocked() async {
    final file = await _ledgerFile();
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_data.toJson()), flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e, st) {
      AppLogger.debug('LocalKioskStore: save failed ($e)');
      AppLogger.debug('$st');
    }
  }
}
