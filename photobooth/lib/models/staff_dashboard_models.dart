/// Parsed payloads for the staff ops dashboard (mirrors web `/staff/dashboard`).
library;

class StaffModeBucket {
  const StaffModeBucket({required this.count, required this.amount});

  final int count;
  final int amount;

  factory StaffModeBucket.fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return const StaffModeBucket(count: 0, amount: 0);
    return StaffModeBucket(
      count: _asInt(raw['count']),
      amount: _asInt(raw['amount']),
    );
  }
}

class StaffDayPaymentsSummary {
  const StaffDayPaymentsSummary({
    required this.totalCount,
    required this.totalAmount,
    required this.upi,
    required this.cash,
    required this.complimentary,
  });

  final int totalCount;
  final int totalAmount;
  final StaffModeBucket upi;
  final StaffModeBucket cash;
  final StaffModeBucket complimentary;

  factory StaffDayPaymentsSummary.fromJson(Map<String, dynamic>? raw) {
    if (raw == null) {
      return const StaffDayPaymentsSummary(
        totalCount: 0,
        totalAmount: 0,
        upi: StaffModeBucket(count: 0, amount: 0),
        cash: StaffModeBucket(count: 0, amount: 0),
        complimentary: StaffModeBucket(count: 0, amount: 0),
      );
    }
    final byMode = raw['byMode'];
    final modes = byMode is Map
        ? Map<String, dynamic>.from(byMode)
        : <String, dynamic>{};
    return StaffDayPaymentsSummary(
      totalCount: _asInt(raw['totalCount']),
      totalAmount: _asInt(raw['totalAmount']),
      upi: StaffModeBucket.fromJson(_asMap(modes['UPI'])),
      cash: StaffModeBucket.fromJson(_asMap(modes['CASH'])),
      complimentary: StaffModeBucket.fromJson(_asMap(modes['COMPLIMENTARY'])),
    );
  }
}

class StaffDaySummary {
  const StaffDaySummary({
    required this.date,
    required this.timezone,
    required this.sessions,
    required this.prints,
    required this.payments,
  });

  final String date;
  final String timezone;
  final int sessions;
  final int prints;
  final StaffDayPaymentsSummary payments;

  factory StaffDaySummary.fromJson(Map<String, dynamic> raw) {
    return StaffDaySummary(
      date: (raw['date'] ?? '').toString(),
      timezone: (raw['timezone'] ?? 'Asia/Kolkata').toString(),
      sessions: _asInt(raw['sessions']),
      prints: _asInt(raw['prints']),
      payments: StaffDayPaymentsSummary.fromJson(_asMap(raw['payments'])),
    );
  }
}

class StaffOpsMember {
  const StaffOpsMember({
    required this.id,
    required this.name,
    required this.staffCode,
    this.kioskId,
  });

  final String id;
  final String name;
  final String staffCode;
  final String? kioskId;

  bool get hasKiosk {
    final id = (kioskId ?? '').trim();
    return id.isNotEmpty;
  }

  factory StaffOpsMember.fromJson(Map<String, dynamic> raw) {
    final kiosk = (raw['kioskId'] ?? raw['kiosk_id'] ?? '').toString().trim();
    return StaffOpsMember(
      id: (raw['id'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      staffCode: (raw['staffCode'] ?? raw['staff_code'] ?? '').toString(),
      kioskId: kiosk.isEmpty ? null : kiosk,
    );
  }
}

class StaffActiveAttendance {
  const StaffActiveAttendance({
    required this.id,
    required this.checkInTime,
  });

  final String id;
  final DateTime? checkInTime;

  factory StaffActiveAttendance.fromJson(Map<String, dynamic> raw) {
    return StaffActiveAttendance(
      id: (raw['id'] ?? '').toString(),
      checkInTime: _asDateTime(raw['checkInTime'] ?? raw['check_in_time']),
    );
  }
}

class StaffOpenRegister {
  const StaffOpenRegister({
    required this.id,
    required this.openedAt,
    required this.receiptsGenerated,
    required this.photosPrinted,
    required this.expectedAmount,
  });

  final String id;
  final DateTime? openedAt;
  final int receiptsGenerated;
  final int photosPrinted;
  final int expectedAmount;

  factory StaffOpenRegister.fromJson(Map<String, dynamic> raw) {
    return StaffOpenRegister(
      id: (raw['id'] ?? '').toString(),
      openedAt: _asDateTime(raw['openedAt'] ?? raw['opened_at']),
      receiptsGenerated: _asInt(
        raw['receiptsGenerated'] ?? raw['receipts_generated'],
      ),
      photosPrinted: _asInt(raw['photosPrinted'] ?? raw['photos_printed']),
      expectedAmount: _asInt(raw['expectedAmount'] ?? raw['expected_amount']),
    );
  }
}

class StaffOpsSession {
  const StaffOpsSession({
    required this.staff,
    required this.isCheckedIn,
    required this.hasOpenRegister,
    this.activeAttendance,
    this.openRegister,
  });

  final StaffOpsMember staff;
  final bool isCheckedIn;
  final bool hasOpenRegister;
  final StaffActiveAttendance? activeAttendance;
  final StaffOpenRegister? openRegister;

  factory StaffOpsSession.fromJson(Map<String, dynamic> raw) {
    final staffRaw = _asMap(raw['staff']) ?? <String, dynamic>{};
    final attendanceRaw = _asMap(raw['activeAttendance']);
    final registerRaw = _asMap(raw['openRegister']);
    return StaffOpsSession(
      staff: StaffOpsMember.fromJson(staffRaw),
      isCheckedIn: raw['isCheckedIn'] == true,
      hasOpenRegister: raw['hasOpenRegister'] == true,
      activeAttendance: attendanceRaw == null
          ? null
          : StaffActiveAttendance.fromJson(attendanceRaw),
      openRegister: registerRaw == null
          ? null
          : StaffOpenRegister.fromJson(registerRaw),
    );
  }
}

class StaffPerformanceStats {
  const StaffPerformanceStats({
    required this.totalReceipts,
    required this.totalPrints,
    required this.totalRevenue,
    required this.totalHours,
  });

  final int totalReceipts;
  final int totalPrints;
  final int totalRevenue;
  final double totalHours;

  factory StaffPerformanceStats.fromJson(Map<String, dynamic> raw) {
    return StaffPerformanceStats(
      totalReceipts: _asInt(raw['totalReceipts']),
      totalPrints: _asInt(raw['totalPrints']),
      totalRevenue: _asInt(raw['totalRevenue']),
      totalHours: _asDouble(raw['totalHours']),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  final s = value?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
