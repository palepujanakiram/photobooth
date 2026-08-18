import '../../models/event_info_model.dart';
import '../../services/event_manager.dart';

/// Persists a verified event or returns an error message. Empty code is a no-op.
Future<String?> bindSplashEventCode({
  required EventManager eventManager,
  required Future<EventInfoModel?> Function(String code, String? kioskCode)
      fetchEvent,
  required String? eventCode,
  required String? kioskCode,
}) async {
  final code = eventCode?.trim().toUpperCase() ?? '';
  if (code.isEmpty) return null;
  final event = await fetchEvent(code, kioskCode);
  if (event == null || !event.isValid || !event.currentlyActive) {
    return 'Invalid or inactive event code. Check with your venue and try again.';
  }
  await eventManager.cacheVerifyResult(
    id: event.id,
    code: event.code,
    photoMode: event.photoMode,
    name: event.name,
    themeCount: event.themeCount,
    frameCount: event.frameCount,
  );
  return null;
}
