import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/event_station_models.dart';
import '../../services/api_service.dart';
import '../../services/event_station_api.dart';
import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';

/// Creates a guest session then the Capture station navigates to the camera.
class EventCaptureStationViewModel extends ChangeNotifier {
  EventCaptureStationViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
    KioskManager? kioskManager,
    EventStationApi? stationApi,
    Duration pollInterval = const Duration(seconds: 4),
  })  : _api = apiService ?? ApiService(),
        _session = sessionManager ?? SessionManager(),
        _kiosk = kioskManager ?? KioskManager(),
        _stationApi = stationApi ?? EventStationApi(),
        _pollInterval = pollInterval;

  final ApiService _api;
  final SessionManager _session;
  final KioskManager _kiosk;
  final EventStationApi _stationApi;
  final Duration _pollInterval;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  EventStationBoard _board = const EventStationBoard();
  String _statusFilter = 'PENDING';

  bool get isBusy => _busy;
  String? get errorMessage => _error;
  bool get hasError => _error != null;
  EventStationStats get stats => _board.stats;
  List<EventCaptureStationItem> get captures => _board.captures;
  String get statusFilter => _statusFilter;
  List<EventCaptureStationItem> get filteredCaptures => itemsForStationStatus(
        captures,
        _statusFilter,
        (item) => item.status,
      );
  List<String> get carouselUrls => captureCarouselUrls(captures);

  void startPolling() {
    _timer?.cancel();
    unawaited(refreshBoard());
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_busy) return;
      unawaited(refreshBoard());
    });
  }

  void setStatusFilter(String status) {
    _statusFilter = status.trim().toUpperCase();
    notifyListeners();
  }

  Future<void> refreshBoard() async {
    try {
      _board = await _stationApi.fetchBoard();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Capture station board failed', error: e, stackTrace: st);
    }
    notifyListeners();
  }

  Future<bool> startNextGuest() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final kioskCode = await _kiosk.getKioskCode();
      final response = await _api.acceptTermsAndCreateSession(
        kioskCode: kioskCode,
        source: 'event-capture',
        groupConsentAccepted: true,
      );
      _session.setSessionFromResponse(response);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Event capture start failed', error: e, stackTrace: st);
      _error = 'Could not start a new guest session.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
