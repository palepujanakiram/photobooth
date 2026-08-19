import 'package:dio/dio.dart';

import '../models/event_station_models.dart';
import '../utils/exceptions.dart';
import 'api_service_dio.dart';
import 'event_manager.dart';
import 'kiosk_manager.dart';

/// HTTP client for event Capture/Theme/Print station queues.
class EventStationApi {
  EventStationApi({
    Dio? dio,
    EventManager? eventManager,
    KioskManager? kioskManager,
    Future<String?> Function()? readKioskCode,
    Future<String?> Function()? readEventCode,
  })  : _dio = dio ?? createProductionApiDio(),
        _eventManager = eventManager ?? EventManager(),
        _readKioskCode = readKioskCode,
        _readEventCode = readEventCode,
        _kioskManager = kioskManager ?? KioskManager();

  final Dio _dio;
  final EventManager _eventManager;
  final KioskManager _kioskManager;
  final Future<String?> Function()? _readKioskCode;
  final Future<String?> Function()? _readEventCode;

  Future<Map<String, dynamic>> _codes({String? deviceId}) async {
    final kiosk =
        ((await (_readKioskCode ?? _kioskManager.getKioskCode)()) ?? '').trim();
    final event =
        ((await (_readEventCode ?? _eventManager.getEventCode)()) ?? '').trim();
    if (kiosk.isEmpty) throw ApiException('kioskCode is required');
    if (event.isEmpty) throw ApiException('eventCode is required');
    return {
      'kioskCode': kiosk,
      'eventCode': event,
      if (deviceId != null && deviceId.trim().isNotEmpty) 'deviceId': deviceId.trim(),
    };
  }

  Future<List<EventThemeStationJob>> listThemeJobs({String status = 'PENDING'}) async {
    final qp = await _codes();
    qp['status'] = status;
    final r = await _dio.get<dynamic>(
      '/api/event/station/theme-jobs',
      queryParameters: qp,
    );
    _throwIfFailed(r, 'Failed to fetch theme jobs');
    return parseEventThemeJobs(r.data)
        .map((j) => j.withStationImageAuth(
              kioskCode: qp['kioskCode'] as String,
              eventCode: qp['eventCode'] as String,
            ))
        .toList();
  }

  Future<EventThemeStationJob> claimThemeJob(String jobId) async {
    final deviceId = await _eventManager.getOrCreateDeviceId();
    final body = await _codes(deviceId: deviceId);
    final r = await _dio.post<dynamic>(
      '/api/event/station/theme-jobs/$jobId/claim',
      data: body,
    );
    _throwIfFailed(r, 'Failed to claim theme job');
    final data = r.data;
    if (data is Map) {
      final job = EventThemeStationJob.fromJson(Map<String, dynamic>.from(data));
      if (job.isValid) {
        return job.withStationImageAuth(
          kioskCode: body['kioskCode'] as String,
          eventCode: body['eventCode'] as String,
        );
      }
    }
    throw ApiException('Failed to claim theme job');
  }

  Future<void> completeThemeJob({
    required String jobId,
    required String themeId,
  }) async {
    final deviceId = await _eventManager.getOrCreateDeviceId();
    final body = await _codes(deviceId: deviceId);
    body['themeId'] = themeId;
    final r = await _dio.post<dynamic>(
      '/api/event/station/theme-jobs/$jobId/complete',
      data: body,
    );
    _throwIfFailed(r, 'Failed to complete theme job');
  }

  Future<List<EventPrintStationJob>> listPrintJobs() async {
    final qp = await _codes();
    final r = await _dio.get<dynamic>(
      '/api/event/station/print-jobs',
      queryParameters: qp,
    );
    _throwIfFailed(r, 'Failed to fetch print jobs');
    return parseEventPrintJobs(r.data)
        .map((j) => j.withStationImageAuth(
              kioskCode: qp['kioskCode'] as String,
              eventCode: qp['eventCode'] as String,
            ))
        .toList();
  }

  Future<EventPrintStationJob> claimPrintJob(String jobId) async {
    final deviceId = await _eventManager.getOrCreateDeviceId();
    final body = await _codes(deviceId: deviceId);
    final r = await _dio.post<dynamic>(
      '/api/event/station/print-jobs/$jobId/claim',
      data: body,
    );
    _throwIfFailed(r, 'Failed to claim print job');
    final data = r.data;
    if (data is Map) {
      final job = EventPrintStationJob.fromJson(Map<String, dynamic>.from(data));
      if (job.isValid) {
        return job.withStationImageAuth(
          kioskCode: body['kioskCode'] as String,
          eventCode: body['eventCode'] as String,
        );
      }
    }
    throw ApiException('Failed to claim print job');
  }

  Future<void> completePrintJob({
    required String jobId,
    required bool success,
    String? error,
  }) async {
    final deviceId = await _eventManager.getOrCreateDeviceId();
    final body = await _codes(deviceId: deviceId);
    body['success'] = success;
    if (error != null && error.trim().isNotEmpty) body['error'] = error.trim();
    final r = await _dio.post<dynamic>(
      '/api/event/station/print-jobs/$jobId/complete',
      data: body,
    );
    _throwIfFailed(r, 'Failed to complete print job');
  }

  Future<EventStationBoard> fetchBoard() async {
    final qp = await _codes();
    final r = await _dio.get<dynamic>(
      '/api/event/station/board',
      queryParameters: qp,
    );
    _throwIfFailed(r, 'Failed to fetch station board');
    return EventStationBoard.fromJson(r.data).withStationImageAuth(
      kioskCode: qp['kioskCode'] as String,
      eventCode: qp['eventCode'] as String,
    );
  }

  Future<EventPrintStationJob> reissuePrintJob(String jobId) async {
    final deviceId = await _eventManager.getOrCreateDeviceId();
    final body = await _codes(deviceId: deviceId);
    final r = await _dio.post<dynamic>(
      '/api/event/station/print-jobs/$jobId/reissue',
      data: body,
    );
    _throwIfFailed(r, 'Failed to reissue print job');
    final data = r.data;
    if (data is Map) {
      final job = EventPrintStationJob.fromJson(Map<String, dynamic>.from(data));
      if (job.isValid) {
        return job.withStationImageAuth(
          kioskCode: body['kioskCode'] as String,
          eventCode: body['eventCode'] as String,
        );
      }
    }
    throw ApiException('Failed to reissue print job');
  }

  void _throwIfFailed(Response<dynamic> r, String fallback) {
    final code = r.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    final data = r.data;
    if (data is Map && data['error'] != null) {
      throw ApiException(data['error'].toString());
    }
    throw ApiException(fallback);
  }
}
