import 'package:dio/dio.dart';

import '../../utils/logger.dart';
import '../api_service_dio.dart';
import '../kiosk_manager.dart';

/// Pipeline flags for the bound event, merged from two ZenAI endpoints.
///
/// `GET /api/event/by-code/:code` is the guest-flow verify call
/// ([ApiService.fetchEventByCode] parses the same response into
/// [EventInfoModel]) and is kept only for its `themeIds` / `frameIds`
/// catalogue — it does not carry `aiEnabled`, `autoPrint`, `defaultCopies`,
/// `printSize`, or a resolved `themeId` / `frameId` at all.
///
/// `GET /api/events/by-code/:code/settings` is the dedicated settings
/// endpoint those fields actually come from. It already applies the
/// backend's own theme/frame fallback (an empty `themeId` there means the
/// event genuinely has none configured, not "ask the catalogue"), so its
/// keys are merged in **over** the verify body rather than the other way
/// round.
///
/// The merged, unwrapped map (no `event` wrapper, no `success` flag) is what
/// [EventPipelineFlags.fromEventJson] and [EventPipelineSync] read.
///
/// Returns null on any failure. The caller decides what an unreachable
/// backend means; here it is never an exception, because a venue with no
/// link is the normal case and not an error condition.
class EventPipelineEventFetch {
  EventPipelineEventFetch({Dio? dio, KioskManager? kiosk})
      : _dio = dio ?? createProductionApiDio(),
        _kiosk = kiosk ?? KioskManager();

  final Dio _dio;
  final KioskManager _kiosk;

  Future<Map<String, dynamic>?> call(String eventCode) async {
    final code = eventCode.trim().toUpperCase();
    if (code.isEmpty) return null;

    final verifyBody = await _get('/api/event/by-code/$code');
    if (verifyBody == null) return null;

    final nested = verifyBody['event'];
    final merged = nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(verifyBody);

    // Best effort: a settings fetch that fails still leaves the verify-derived
    // catalogue and event metadata usable, same as before this endpoint
    // existed. Only a failed verify call aborts the whole sync.
    final settings = await _getSettings(code);
    if (settings != null) merged.addAll(settings);

    return merged;
  }

  Future<Map<String, dynamic>?> _getSettings(String code) async {
    final qp = <String, dynamic>{};
    final kioskCode = (await _kiosk.getKioskCode())?.trim().toUpperCase();
    if (kioskCode != null && kioskCode.isNotEmpty) {
      qp['kioskCode'] = kioskCode;
    }
    return _get(
      '/api/events/by-code/$code/settings',
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final r = await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
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
      AppLogger.warning('Event sync fetch failed for $path: $e');
      return null;
    }
  }
}
