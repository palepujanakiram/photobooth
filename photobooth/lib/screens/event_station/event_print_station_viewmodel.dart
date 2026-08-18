import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../models/event_station_models.dart';
import '../../services/api_service.dart';
import '../../services/event_station_api.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';

typedef EventStationPrintFn = Future<void> Function(
  XFile imageFile, {
  required String printSize,
});

/// Polls event print jobs and prints on the kiosk's DNP/Selphy.
class EventPrintStationViewModel extends ChangeNotifier {
  EventPrintStationViewModel({
    EventStationApi? api,
    ApiService? mediaApi,
    EventStationPrintFn? printFn,
    Future<XFile> Function(String url)? downloadImage,
    Duration pollInterval = const Duration(seconds: 4),
  })  : _api = api ?? EventStationApi(),
        _printFn = printFn,
        _download = downloadImage ??
            ((url) => (mediaApi ?? ApiService()).downloadImageToTemp(url)),
        _pollInterval = pollInterval;

  final EventStationApi _api;
  final EventStationPrintFn? _printFn;
  final Future<XFile> Function(String url) _download;
  final Duration _pollInterval;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  List<EventPrintStationJob> _queue = const [];
  EventPrintStationJob? _active;

  bool get isBusy => _busy;
  String? get errorMessage => _error;
  List<EventPrintStationJob> get queue => _queue;
  EventPrintStationJob? get active => _active;

  void startPolling() {
    _timer?.cancel();
    unawaited(refreshQueue());
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_busy) return;
      unawaited(refreshQueue());
    });
  }

  Future<void> refreshQueue() async {
    try {
      _queue = await _api.listPrintJobs();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Print station poll failed', error: e, stackTrace: st);
    }
    notifyListeners();
  }

  Future<bool> printNext() async {
    if (_busy || _queue.isEmpty) return false;
    return printJob(_queue.first);
  }

  Future<bool> printJob(EventPrintStationJob job) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _active = job;
    notifyListeners();
    EventPrintStationJob? claimed;
    try {
      claimed = await _api.claimPrintJob(job.id);
      final file = await _download(claimed.imageUrl);
      final printer = _printFn;
      if (printer != null) {
        await printer(file, printSize: claimed.printSize);
      }
      await _api.completePrintJob(jobId: claimed.id, success: true);
      _active = null;
      await refreshQueue();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      if (claimed != null) await _failActive(claimed.id, e.message);
      return false;
    } catch (e, st) {
      AppLogger.error('Print station job failed', error: e, stackTrace: st);
      _error = AppStrings.printFailedGeneric;
      if (claimed != null) await _failActive(claimed.id, e.toString());
      return false;
    } finally {
      _busy = false;
      _active = null;
      notifyListeners();
    }
  }

  Future<void> _failActive(String jobId, String message) async {
    try {
      await _api.completePrintJob(jobId: jobId, success: false, error: message);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
