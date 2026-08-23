import 'local_kiosk_models.dart';

const kKioskLedgerVersion = 1;

class KioskLedgerData {
  KioskLedgerData({
    this.currentSessionId,
    Map<String, LocalSessionRow>? sessions,
    Map<String, LocalEntityRow>? payments,
    Map<String, LocalEntityRow>? printJobs,
    Map<String, LocalEntityRow>? receipts,
    Map<String, int>? invoiceSequences,
    Map<String, KioskOutboxEntry>? outbox,
    Map<String, int>? syncedAssets,
  })  : sessions = sessions ?? <String, LocalSessionRow>{},
        payments = payments ?? <String, LocalEntityRow>{},
        printJobs = printJobs ?? <String, LocalEntityRow>{},
        receipts = receipts ?? <String, LocalEntityRow>{},
        invoiceSequences = invoiceSequences ?? <String, int>{},
        outbox = outbox ?? <String, KioskOutboxEntry>{},
        syncedAssets = syncedAssets ?? <String, int>{};

  String? currentSessionId;
  final Map<String, LocalSessionRow> sessions;
  final Map<String, LocalEntityRow> payments;
  final Map<String, LocalEntityRow> printJobs;
  final Map<String, LocalEntityRow> receipts;
  final Map<String, int> invoiceSequences;
  final Map<String, KioskOutboxEntry> outbox;
  final Map<String, int> syncedAssets;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': kKioskLedgerVersion,
        'currentSessionId': currentSessionId,
        'sessions': {
          for (final e in sessions.entries) e.key: e.value.toJson(),
        },
        'payments': {
          for (final e in payments.entries) e.key: e.value.toJson(),
        },
        'printJobs': {
          for (final e in printJobs.entries) e.key: e.value.toJson(),
        },
        'receipts': {
          for (final e in receipts.entries) e.key: e.value.toJson(),
        },
        'invoiceSequences': invoiceSequences,
        'outbox': {
          for (final e in outbox.entries) e.key: e.value.toJson(),
        },
        'syncedAssets': syncedAssets,
      };

  static KioskLedgerData fromJson(Object? raw) {
    if (raw is! Map) return KioskLedgerData();
    final json = jsonMap(raw);
    return KioskLedgerData(
      currentSessionId: json['currentSessionId'] as String?,
      sessions: _sessionRows(json['sessions']),
      payments: _entityRows(json['payments']),
      printJobs: _entityRows(json['printJobs']),
      receipts: _entityRows(json['receipts']),
      invoiceSequences: _intMap(json['invoiceSequences']),
      outbox: _outboxRows(json['outbox']),
      syncedAssets: _intMap(json['syncedAssets']),
    );
  }

  void recoverInFlightOutbox() {
    final ids = outbox.keys.toList();
    for (final id in ids) {
      final row = outbox[id];
      if (row != null && row.status == KioskOutboxStatus.syncing) {
        outbox[id] = row.copyWith(status: KioskOutboxStatus.pending);
      }
    }
  }
}

Map<String, LocalSessionRow> _sessionRows(Object? raw) {
  final map = jsonMap(raw);
  final out = <String, LocalSessionRow>{};
  for (final entry in map.entries) {
    out[entry.key] = LocalSessionRow.fromJson(jsonMap(entry.value));
  }
  return out;
}

Map<String, LocalEntityRow> _entityRows(Object? raw) {
  final map = jsonMap(raw);
  final out = <String, LocalEntityRow>{};
  for (final entry in map.entries) {
    out[entry.key] = LocalEntityRow.fromJson(jsonMap(entry.value));
  }
  return out;
}

Map<String, KioskOutboxEntry> _outboxRows(Object? raw) {
  final map = jsonMap(raw);
  final out = <String, KioskOutboxEntry>{};
  for (final entry in map.entries) {
    out[entry.key] = KioskOutboxEntry.fromJson(jsonMap(entry.value));
  }
  return out;
}

Map<String, int> _intMap(Object? raw) {
  final map = jsonMap(raw);
  final out = <String, int>{};
  for (final entry in map.entries) {
    out[entry.key] = jsonInt(entry.value);
  }
  return out;
}
