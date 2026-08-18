import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/event_station_models.dart';
import '../../screens/theme_selection/theme_model.dart';
import '../../services/event_station_api.dart';
import '../../services/theme_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';

/// Polls event theme-assignment jobs and completes a guest look pick.
class EventThemeStationViewModel extends ChangeNotifier {
  EventThemeStationViewModel({
    EventStationApi? api,
    Future<List<ThemeModel>> Function()? loadThemes,
    Duration pollInterval = const Duration(seconds: 3),
  })  : _api = api ?? EventStationApi(),
        _loadThemes = loadThemes ?? (() => ThemeManager().fetchThemes()),
        _pollInterval = pollInterval;

  final EventStationApi _api;
  final Future<List<ThemeModel>> Function() _loadThemes;
  final Duration _pollInterval;

  Timer? _timer;
  bool _busy = false;
  String? _error;
  List<EventThemeStationJob> _queue = const [];
  EventThemeStationJob? _claimed;
  List<ThemeModel> _looks = const [];
  String? _selectedThemeId;

  bool get isBusy => _busy;
  String? get errorMessage => _error;
  List<EventThemeStationJob> get queue => _queue;
  EventThemeStationJob? get claimed => _claimed;
  List<ThemeModel> get looks => _looks;
  String? get selectedThemeId => _selectedThemeId;
  bool get hasClaimedJob => _claimed != null;

  void startPolling() {
    _timer?.cancel();
    unawaited(refreshQueue());
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_claimed != null || _busy) return;
      unawaited(refreshQueue());
    });
  }

  Future<void> refreshQueue() async {
    try {
      _queue = await _api.listThemeJobs();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Theme station poll failed', error: e, stackTrace: st);
    }
    notifyListeners();
  }

  Future<bool> claimNext() async {
    if (_busy || _queue.isEmpty) return false;
    return claimJob(_queue.first.id);
  }

  Future<bool> claimJob(String jobId) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _claimed = await _api.claimThemeJob(jobId);
      _looks = await _loadThemes();
      _selectedThemeId = _looks.isEmpty ? null : _looks.first.id;
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _claimed = null;
      return false;
    } catch (e, st) {
      AppLogger.error('Theme station claim failed', error: e, stackTrace: st);
      _error = AppStrings.eventStationJobClaimed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void selectTheme(String themeId) {
    _selectedThemeId = themeId;
    notifyListeners();
  }

  Future<bool> completeSelected() async {
    final job = _claimed;
    final themeId = _selectedThemeId;
    if (_busy || job == null || themeId == null || themeId.isEmpty) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _api.completeThemeJob(jobId: job.id, themeId: themeId);
      _claimed = null;
      _selectedThemeId = null;
      _looks = const [];
      await refreshQueue();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Theme station complete failed', error: e, stackTrace: st);
      _error = 'Could not save this look. Try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void releaseClaimed() {
    _claimed = null;
    _selectedThemeId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
