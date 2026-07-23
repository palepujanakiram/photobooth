import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/staff_dashboard_models.dart';
import 'package:photobooth/screens/staff/staff_dashboard_helpers.dart';
import 'package:photobooth/screens/staff/staff_dashboard_viewmodel.dart';
import 'package:photobooth/utils/exceptions.dart';

class _FakeGateway implements StaffDashboardGateway {
  StaffOpsSession session = const StaffOpsSession(
    staff: StaffOpsMember(id: 's1', name: 'Ada', staffCode: 'EMP1'),
    isCheckedIn: false,
    hasOpenRegister: false,
  );
  StaffDaySummary daySummary = StaffDaySummary.fromJson({
    'date': '2026-07-20',
    'timezone': 'Asia/Kolkata',
    'sessions': 3,
    'prints': 2,
    'payments': {
      'totalCount': 2,
      'totalAmount': 500,
      'byMode': {
        'UPI': {'count': 1, 'amount': 300},
        'CASH': {'count': 1, 'amount': 200},
        'COMPLIMENTARY': {'count': 0, 'amount': 0},
      },
    },
  });
  StaffPerformanceStats? stats = const StaffPerformanceStats(
    totalReceipts: 10,
    totalPrints: 8,
    totalRevenue: 4000,
    totalHours: 12.5,
  );
  ApiException? failNext;
  bool throwUnexpected = false;
  int checkInCalls = 0;
  int logoutCalls = 0;

  @override
  Future<StaffOpsSession> fetchStaffOpsSession() async {
    _throwIfNeeded();
    return session;
  }

  @override
  Future<StaffDaySummary> fetchDaySummary({required String date}) async {
    _throwIfNeeded();
    return daySummary;
  }

  @override
  Future<StaffPerformanceStats?> fetchStaffStats(String staffId) async {
    _throwIfNeeded();
    return stats;
  }

  @override
  Future<void> checkIn() async {
    _throwIfNeeded();
    checkInCalls++;
    session = StaffOpsSession(
      staff: session.staff,
      isCheckedIn: true,
      hasOpenRegister: false,
      activeAttendance: StaffActiveAttendance(
        id: 'a1',
        checkInTime: DateTime.utc(2026, 7, 20, 4),
      ),
    );
  }

  @override
  Future<void> checkOut() async {
    _throwIfNeeded();
    session = StaffOpsSession(
      staff: session.staff,
      isCheckedIn: false,
      hasOpenRegister: false,
    );
  }

  @override
  Future<void> openRegister({required int openingFloat}) async {
    _throwIfNeeded();
    session = StaffOpsSession(
      staff: session.staff,
      isCheckedIn: true,
      hasOpenRegister: true,
      openRegister: StaffOpenRegister(
        id: 'r1',
        openedAt: DateTime.utc(2026, 7, 20, 5),
        receiptsGenerated: 0,
        photosPrinted: 0,
        expectedAmount: openingFloat,
      ),
    );
  }

  @override
  Future<void> closeRegister({
    required int closingFloat,
    required int actualAmount,
    String closingNotes = '',
  }) async {
    _throwIfNeeded();
    session = StaffOpsSession(
      staff: session.staff,
      isCheckedIn: true,
      hasOpenRegister: false,
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  void _throwIfNeeded() {
    if (throwUnexpected) {
      throw StateError('boom');
    }
    final e = failNext;
    if (e != null) {
      failNext = null;
      throw e;
    }
  }
}

void main() {
  group('StaffDashboardHelpers', () {
    test('validates iso dates', () {
      expect(StaffDashboardHelpers.isValidIsoDate('2026-07-20'), isTrue);
      expect(StaffDashboardHelpers.isValidIsoDate('20-07-2026'), isFalse);
      expect(StaffDashboardHelpers.isValidIsoDate(''), isFalse);
    });

    test('formats day label', () {
      expect(
        StaffDashboardHelpers.formatDayLabel('2026-07-20'),
        contains('Jul'),
      );
      expect(StaffDashboardHelpers.formatDayLabel('bad'), 'bad');
    });

    test('formats elapsed duration', () {
      final start = DateTime.utc(2026, 7, 20, 10);
      final now = DateTime.utc(2026, 7, 20, 12, 15);
      expect(
        StaffDashboardHelpers.formatElapsed(start, now: now),
        '2h 15m',
      );
      expect(
        StaffDashboardHelpers.formatElapsed(now, now: start),
        '0h 0m',
      );
    });

    test('formats inr', () {
      expect(StaffDashboardHelpers.formatInr(970), '₹970');
    });

    test('todayLocalDate is YYYY-MM-DD', () {
      expect(
        StaffDashboardHelpers.isValidIsoDate(
          StaffDashboardHelpers.todayLocalDate(),
        ),
        isTrue,
      );
    });

    test('formatElapsed uses DateTime.now when now omitted', () {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      final label = StaffDashboardHelpers.formatElapsed(start);
      expect(label, contains('h'));
      expect(label, contains('m'));
    });
  });

  group('StaffDaySummary.fromJson', () {
    test('parses day KPIs and mode split', () {
      final s = StaffDaySummary.fromJson({
        'date': '2026-07-20',
        'timezone': 'Asia/Kolkata',
        'sessions': 4,
        'prints': 3,
        'payments': {
          'totalCount': 2,
          'totalAmount': 500,
          'byMode': {
            'UPI': {'count': 1, 'amount': 300},
            'CASH': {'count': 1, 'amount': 200},
          },
        },
      });
      expect(s.sessions, 4);
      expect(s.payments.upi.amount, 300);
      expect(s.payments.complimentary.count, 0);
    });

    test('tolerates missing byMode and stringy numbers', () {
      final s = StaffDaySummary.fromJson({
        'date': '2026-07-20',
        'sessions': '2',
        'prints': 1.6,
        'payments': {
          'totalCount': '1',
          'totalAmount': 10.4,
          'byMode': 'nope',
        },
      });
      expect(s.sessions, 2);
      expect(s.prints, 2);
      expect(s.payments.totalAmount, 10);
      expect(s.payments.upi.count, 0);
    });
  });

  group('StaffOpsSession.fromJson', () {
    test('parses shift and register', () {
      final s = StaffOpsSession.fromJson({
        'staff': {
          'id': '1',
          'name': 'Ada',
          'staffCode': 'EMP1',
          'kioskId': 'kiosk-1',
        },
        'isCheckedIn': true,
        'hasOpenRegister': true,
        'activeAttendance': {
          'id': 'a1',
          'checkInTime': '2026-07-20T04:00:00.000Z',
        },
        'openRegister': {
          'id': 'r1',
          'openedAt': '2026-07-20T05:00:00.000Z',
          'receiptsGenerated': 2,
          'photosPrinted': 1,
          'expectedAmount': 400,
        },
      });
      expect(s.staff.name, 'Ada');
      expect(s.staff.hasKiosk, isTrue);
      expect(s.isCheckedIn, isTrue);
      expect(s.openRegister?.expectedAmount, 400);
    });
  });

  group('StaffPerformanceStats.fromJson', () {
    test('parses totals', () {
      final s = StaffPerformanceStats.fromJson({
        'totalReceipts': 10,
        'totalPrints': 8,
        'totalRevenue': 4000,
        'totalHours': 12.5,
      });
      expect(s.totalReceipts, 10);
      expect(s.totalHours, 12.5);
    });

    test('parses string hours', () {
      final s = StaffPerformanceStats.fromJson({
        'totalReceipts': 1,
        'totalPrints': 1,
        'totalRevenue': 1,
        'totalHours': '3.25',
      });
      expect(s.totalHours, 3.25);
    });
  });

  group('StaffDashboardViewModel', () {
    test('defaults initial date to today when omitted', () {
      final vm = StaffDashboardViewModel(gateway: _FakeGateway());
      expect(vm.selectedDate, StaffDashboardHelpers.todayLocalDate());
    });

    test('loadAll populates session summary and stats', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      expect(vm.session?.staff.name, 'Ada');
      expect(vm.daySummary?.sessions, 3);
      expect(vm.stats?.totalHours, 12.5);
      expect(vm.loading, isFalse);
    });

    test('checkIn and checkOut update session', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      await vm.checkIn();
      expect(gw.checkInCalls, 1);
      expect(vm.session?.isCheckedIn, isTrue);
      await vm.checkOut();
      expect(vm.session?.isCheckedIn, isFalse);
    });

    test('setSelectedDate ignores invalid and refreshes on change', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      await vm.setSelectedDate('nope');
      expect(vm.selectedDate, '2026-07-20');
      await vm.setSelectedDate('2026-07-19');
      expect(vm.selectedDate, '2026-07-19');
    });

    test('jumpToToday sets today', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-01-01',
      );
      await vm.jumpToToday();
      expect(vm.selectedDate, StaffDashboardHelpers.todayLocalDate());
      expect(vm.isViewingToday, isTrue);
    });

    test('loadAll surfaces api errors', () async {
      final gw = _FakeGateway()..failNext = ApiException('boom', 500);
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await expectLater(vm.loadAll(), throwsA(isA<ApiException>()));
      expect(vm.error, 'boom');
      expect(vm.loading, isFalse);
    });

    test('loadAll surfaces unexpected errors', () async {
      final gw = _FakeGateway()..throwUnexpected = true;
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await expectLater(vm.loadAll(), throwsA(isA<StateError>()));
      expect(vm.error, contains('Failed to load dashboard'));
    });

    test('action failure sets error without rethrow', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      gw.failNext = ApiException('register busy');
      await vm.openRegister(openingFloat: 0);
      expect(vm.error, 'register busy');
      expect(vm.actionBusy, isFalse);
    });

    test('action unexpected error is captured', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      gw.throwUnexpected = true;
      await vm.checkIn();
      expect(vm.error, contains('boom'));
    });

    test('refreshQuiet captures unexpected errors', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      gw.throwUnexpected = true;
      await vm.refreshQuiet();
      expect(vm.error, contains('Refresh failed'));
    });

    test('clearError and logout', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      gw.failNext = ApiException('x');
      await vm.refreshQuiet();
      expect(vm.error, 'x');
      vm.clearError();
      expect(vm.error, isNull);
      await vm.logout();
      expect(gw.logoutCalls, 1);
    });

    test('open and close register', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      await vm.loadAll();
      await vm.checkIn();
      await vm.openRegister(openingFloat: 500);
      expect(vm.session?.hasOpenRegister, isTrue);
      await vm.closeRegister(closingFloat: 100, actualAmount: 600);
      expect(vm.session?.hasOpenRegister, isFalse);
    });

    test('loadAll ignores concurrent calls', () async {
      final gw = _FakeGateway();
      final vm = StaffDashboardViewModel(
        gateway: gw,
        initialDate: '2026-07-20',
      );
      final a = vm.loadAll();
      final b = vm.loadAll();
      await Future.wait([a, b]);
      expect(vm.session, isNotNull);
    });
  });
}
