import 'package:dio/dio.dart';

import '../../utils/logger.dart';
import '../api_service_dio.dart';

/// Raw `GET /api/event/by-code/:code` body, for the pipeline flags.
///
/// [ApiService.fetchEventByCode] parses the same endpoint into
/// [EventInfoModel], which keeps only the guest-flow fields and drops every
/// pipeline one. Rather than widen that model — the whole point of parsing
/// flags separately is that the guest flow stays untouched — this returns the
/// body as it arrived and lets `EventPipelineFlags.fromEventJson` read it.
///
/// Returns null on any failure. The caller decides what an unreachable backend
/// means; here it is never an exception, because a venue with no link is the
/// normal case and not an error condition.
class EventPipelineEventFetch {
  EventPipelineEventFetch({Dio? dio}) : _dio = dio ?? createProductionApiDio();

  final Dio _dio;

  Future<Map<String, dynamic>?> call(String eventCode) async {
    final code = eventCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    try {
      final r = await _dio.get<dynamic>(
        '/api/event/by-code/$code',
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (c) => c != null && c >= 200 && c < 500,
        ),
      );
      if (r.statusCode != null && r.statusCode! >= 400) return null;
      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (e) {
      AppLogger.warning('Event sync fetch failed for $code: $e');
      return null;
    }
  }
}
