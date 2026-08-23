// SQLite-shaped kiosk ledger row types (sessions, outbox, invoice series).

abstract final class KioskOutboxEntity {
  static const session = 'session';
  static const payment = 'payment';
  static const printJob = 'print_job';
  static const receipt = 'receipt';
  static const asset = 'asset';

  static const Set<String> all = {
    session,
    payment,
    printJob,
    receipt,
    asset,
  };

  static int priority(String entityType) {
    switch (entityType) {
      case session:
        return 0;
      case payment:
        return 1;
      case printJob:
        return 2;
      case receipt:
        return 3;
      case asset:
        return 4;
      default:
        return 9;
    }
  }

  static int compare(KioskOutboxEntry a, KioskOutboxEntry b) {
    final byType = priority(a.entityType).compareTo(priority(b.entityType));
    if (byType != 0) return byType;
    return a.createdAtMs.compareTo(b.createdAtMs);
  }
}

abstract final class KioskOutboxStatus {
  static const pending = 'PENDING';
  static const syncing = 'SYNCING';
  static const done = 'DONE';
  static const failed = 'FAILED';
}

class LocalSessionWrite {
  const LocalSessionWrite({
    required this.id,
    required this.payload,
    this.kioskCode,
    this.paymentStatus,
    this.setCurrent = true,
    this.enqueueOutbox = true,
  });

  final String id;
  final Map<String, dynamic> payload;
  final String? kioskCode;
  final String? paymentStatus;
  final bool setCurrent;
  final bool enqueueOutbox;
}

class KioskOutboxEntry {
  const KioskOutboxEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> payload;
  final String status;
  final int attempts;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'payload': payload,
        'status': status,
        'attempts': attempts,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory KioskOutboxEntry.fromJson(Map<String, dynamic> json) {
    return KioskOutboxEntry(
      id: json['id'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      payload: jsonMap(json['payload']),
      status: json['status'] as String? ?? KioskOutboxStatus.pending,
      attempts: jsonInt(json['attempts']),
      createdAtMs: jsonInt(json['createdAtMs']),
      updatedAtMs: jsonInt(json['updatedAtMs']),
    );
  }

  KioskOutboxEntry copyWith({
    Map<String, dynamic>? payload,
    String? status,
    int? attempts,
    int? updatedAtMs,
  }) {
    return KioskOutboxEntry(
      id: id,
      entityType: entityType,
      entityId: entityId,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

class LocalDayCounts {
  const LocalDayCounts({
    required this.sessions,
    required this.payments,
    required this.printJobs,
    required this.receipts,
  });

  final int sessions;
  final int payments;
  final int printJobs;
  final int receipts;
}

class LocalEntityRow {
  const LocalEntityRow({
    required this.id,
    required this.sessionId,
    required this.payload,
    required this.createdAtMs,
    this.receiptNumber,
  });

  final String id;
  final String sessionId;
  final Map<String, dynamic> payload;
  final int createdAtMs;
  final String? receiptNumber;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sessionId': sessionId,
        'payload': payload,
        'createdAtMs': createdAtMs,
        if (receiptNumber != null) 'receiptNumber': receiptNumber,
      };

  factory LocalEntityRow.fromJson(Map<String, dynamic> json) {
    return LocalEntityRow(
      id: json['id'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      payload: jsonMap(json['payload']),
      createdAtMs: jsonInt(json['createdAtMs']),
      receiptNumber: json['receiptNumber'] as String?,
    );
  }
}

class LocalSessionRow {
  const LocalSessionRow({
    required this.id,
    required this.payload,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.kioskCode,
    this.paymentStatus,
  });

  final String id;
  final Map<String, dynamic> payload;
  final String? kioskCode;
  final String? paymentStatus;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'payload': payload,
        'kioskCode': kioskCode,
        'paymentStatus': paymentStatus,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory LocalSessionRow.fromJson(Map<String, dynamic> json) {
    return LocalSessionRow(
      id: json['id'] as String? ?? '',
      payload: jsonMap(json['payload']),
      kioskCode: json['kioskCode'] as String?,
      paymentStatus: json['paymentStatus'] as String?,
      createdAtMs: jsonInt(json['createdAtMs']),
      updatedAtMs: jsonInt(json['updatedAtMs']),
    );
  }
}

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

int jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}
