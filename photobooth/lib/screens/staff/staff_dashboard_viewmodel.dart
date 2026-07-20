import 'package:flutter/foundation.dart';

import '../../models/staff_dashboard_models.dart';
import '../../utils/exceptions.dart';
import 'staff_dashboard_helpers.dart';

/// Narrow API surface for the staff dashboard (testable without Dio).
abstract class StaffDashboardGateway {
  Future<StaffOpsSession> fetchStaffOpsSession();
  Future<StaffDaySummary> fetchDaySummary({required String date});
  Future<StaffPerformanceStats?> fetchStaffStats(String staffId);
  Future<void> checkIn();
  Future<void> checkOut();
  Future<void> openRegister({required int openingFloat});
  Future<void> closeRegister({
    required int closingFloat,
    required int actualAmount,
    String closingNotes = '',
  });
  Future<void> logout();
}

/// Business logic for the staff ops dashboard (web `/staff/dashboard` parity).
class StaffDashboardViewModel extends ChangeNotifier {
  StaffDashboardViewModel({
    required StaffDashboardGateway gateway,
    String? initialDate,
  })  : _gateway = gateway,
        _selectedDate =
            initialDate ?? StaffDashboardHelpers.todayLocalDate();

  final StaffDashboardGateway _gateway;

  String _selectedDate;
  StaffOpsSession? _session;
  StaffDaySummary? _daySummary;
  StaffPerformanceStats? _stats;
  bool _loading = false;
  bool _actionBusy = false;
  String? _error;

  String get selectedDate => _selectedDate;
  StaffOpsSession? get session => _session;
  StaffDaySummary? get daySummary => _daySummary;
  StaffPerformanceStats? get stats => _stats;
  bool get loading => _loading;
  bool get actionBusy => _actionBusy;
  String? get error => _error;
  bool get isViewingToday =>
      _selectedDate == StaffDashboardHelpers.todayLocalDate();

  Future<void> loadAll() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([
        _refreshSession(),
        _refreshDaySummary(),
      ]);
      final staffId = _session?.staff.id.trim() ?? '';
      if (staffId.isNotEmpty) {
        _stats = await _gateway.fetchStaffStats(staffId);
      }
    } on ApiException catch (e) {
      _error = e.message;
      rethrow;
    } catch (e) {
      _error = 'Failed to load dashboard: $e';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshQuiet() async {
    try {
      await Future.wait([
        _refreshSession(),
        _refreshDaySummary(),
      ]);
      final staffId = _session?.staff.id.trim() ?? '';
      if (staffId.isNotEmpty) {
        _stats = await _gateway.fetchStaffStats(staffId);
      }
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Refresh failed: $e';
    }
    notifyListeners();
  }

  Future<void> setSelectedDate(String isoDate) async {
    final next = isoDate.trim();
    if (!StaffDashboardHelpers.isValidIsoDate(next)) return;
    if (next == _selectedDate) return;
    _selectedDate = next;
    notifyListeners();
    await refreshQuiet();
  }

  Future<void> jumpToToday() async {
    await setSelectedDate(StaffDashboardHelpers.todayLocalDate());
  }

  Future<void> checkIn() => _runAction(() => _gateway.checkIn());

  Future<void> checkOut() => _runAction(() => _gateway.checkOut());

  Future<void> openRegister({required int openingFloat}) =>
      _runAction(() => _gateway.openRegister(openingFloat: openingFloat));

  Future<void> closeRegister({
    required int closingFloat,
    required int actualAmount,
    String closingNotes = '',
  }) =>
      _runAction(
        () => _gateway.closeRegister(
          closingFloat: closingFloat,
          actualAmount: actualAmount,
          closingNotes: closingNotes,
        ),
      );

  Future<void> logout() => _gateway.logout();

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    _actionBusy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      await _refreshSession();
      await _refreshDaySummary();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshSession() async {
    _session = await _gateway.fetchStaffOpsSession();
  }

  Future<void> _refreshDaySummary() async {
    _daySummary = await _gateway.fetchDaySummary(date: _selectedDate);
  }
}
