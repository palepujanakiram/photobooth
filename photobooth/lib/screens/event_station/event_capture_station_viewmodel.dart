import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../models/event_station_models.dart';
import '../../services/api_service.dart';
import '../../services/event_station_api.dart';
import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/event_bulk_import.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';

/// Creates a guest session then the Capture station navigates to the camera.
class EventCaptureStationViewModel extends ChangeNotifier {
  EventCaptureStationViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
    KioskManager? kioskManager,
    EventStationApi? stationApi,
    Duration pollInterval = const Duration(seconds: 6),
    EventCaptureImportHooks? importHooks,
  })  : _api = apiService ?? ApiService(),
        _session = sessionManager ?? SessionManager(),
        _kiosk = kioskManager ?? KioskManager(),
        _stationApi = stationApi ?? EventStationApi(),
        _pollInterval = pollInterval,
        _importHooks = importHooks;

  final ApiService _api;
  final SessionManager _session;
  final KioskManager _kiosk;
  final EventStationApi _stationApi;
  final Duration _pollInterval;
  final EventCaptureImportHooks? _importHooks;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  EventStationBoard _board = const EventStationBoard();
  String _statusFilter = 'ALL';
  List<EventBulkImportItem> _importItems = const [];
  EventBulkImportProgress? _importProgress;

  bool get isBusy => _busy;
  String? get errorMessage => _error;
  bool get hasError => _error != null;
  EventStationStats get stats => _board.stats;
  EventDeliveryStats get delivery => _board.delivery;
  List<EventCaptureStationItem> get captures => _board.captures;
  String get statusFilter => _statusFilter;
  List<EventCaptureStationItem> get filteredCaptures => itemsForStationStatus(
        captures,
        _statusFilter,
        (item) => item.status,
      );
  List<String> get carouselUrls => captureCarouselUrls(captures);
  List<EventBulkImportItem> get importItems => _importItems;
  EventBulkImportProgress? get importProgress => _importProgress;
  bool get hasImportTray => _importItems.isNotEmpty;

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

  Future<void> refreshBoard({bool clearErrorOnSuccess = true}) async {
    try {
      final next = await _stationApi.fetchBoard();
      if (identical(next, _board) && _error == null) {
        if (clearErrorOnSuccess) _error = null;
        return;
      }
      _board = next;
      if (clearErrorOnSuccess) _error = null;
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

  Future<void> pickFromCard() async {
    if (_busy) return;
    final pick = _importHooks?.pickImages;
    if (pick == null) {
      _error = AppStrings.eventStationImportUnavailable;
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _appendPickedFiles(await pick());
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Event card import pick failed', error: e, stackTrace: st);
      _error = AppStrings.eventStationImportFailed;
    } finally {
      _busy = false;
      _importProgress = null;
      notifyListeners();
    }
  }

  void toggleImportSelection(String id) {
    _importItems = toggleEventImportSelection(_importItems, id);
    notifyListeners();
  }

  void discardSelectedImport() {
    if (eventImportSelected(_importItems).isEmpty) {
      _error = AppStrings.eventStationImportNoneSelected;
      notifyListeners();
      return;
    }
    _importItems = discardEventImportSelected(_importItems);
    _error = null;
    notifyListeners();
  }

  void clearImportTray() {
    _importItems = const [];
    _error = null;
    notifyListeners();
  }

  Future<int> importSelectedAsGuests() async {
    if (_busy) return 0;
    final selected = eventImportSelected(_importItems);
    if (selected.isEmpty) {
      _error = AppStrings.eventStationImportNoneSelected;
      notifyListeners();
      return 0;
    }
    _busy = true;
    _error = null;
    _importProgress = EventBulkImportProgress(
      done: 0,
      total: selected.length,
    );
    notifyListeners();
    final importedIds = <String>{};
    try {
      await _uploadSelectedGuests(selected, importedIds);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Event card import failed', error: e, stackTrace: st);
      _error = AppStrings.eventStationImportFailed;
    } finally {
      _importItems =
          _importItems.where((item) => !importedIds.contains(item.id)).toList();
      _busy = false;
      _importProgress = null;
    }
    await refreshBoard(clearErrorOnSuccess: _error == null);
    return importedIds.length;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _appendPickedFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    _importProgress = EventBulkImportProgress(
      done: 0,
      total: files.length,
      phase: EventBulkImportPhase.reading,
    );
    notifyListeners();
    final items = await eventBulkImportItemsFromXFiles(
      files,
      batchId: 'b${DateTime.now().microsecondsSinceEpoch}',
      onProgress: (done, total) {
        _importProgress = EventBulkImportProgress(
          done: done,
          total: total,
          phase: EventBulkImportPhase.reading,
        );
        notifyListeners();
      },
    );
    if (items.isEmpty) {
      _error = AppStrings.eventStationImportEmptyPick;
      return;
    }
    _importItems = sortEventImportItems([..._importItems, ...items]);
  }

  Future<void> _uploadSelectedGuests(
    List<EventBulkImportItem> selected,
    Set<String> importedIds,
  ) async {
    for (final item in selected) {
      await _importOnePhoto(item);
      importedIds.add(item.id);
      _importProgress = EventBulkImportProgress(
        done: importedIds.length,
        total: selected.length,
      );
      notifyListeners();
    }
  }

  Future<void> _importOnePhoto(EventBulkImportItem item) async {
    final kioskCode = await _kiosk.getKioskCode();
    final response = await _api.acceptTermsAndCreateSession(
      kioskCode: kioskCode,
      source: kEventSdImportSource,
      groupConsentAccepted: true,
    );
    final sessionId = eventSessionIdFromCreateResponse(response);
    if (sessionId == null) {
      throw ApiException(AppStrings.eventStationImportMissingSession);
    }
    _session.setSessionFromResponse(response);
    await _api.updateSession(
      sessionId: sessionId,
      userImageUrl: eventImportBytesToDataUrl(item.bytes, item.mime),
    );
  }
}
