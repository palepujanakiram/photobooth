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
  if (event != null && event.isValid && event.currentlyActive) {
    await eventManager.cacheVerifyResult(
      id: event.id,
      code: event.code,
      photoMode: event.photoMode,
      name: event.name,
      themeCount: event.themeCount,
      frameCount: event.frameCount,
      themeIds: event.themeIds,
      frameIds: event.frameIds,
    );
    return null;
  }
  // Offline / verify failed: restore the durable row for this exact event.
  final diskEvent = await eventManager.readCachedEvent(code);
  if (diskEvent != null && diskEvent.currentlyActive) {
    await eventManager.cacheVerifyResult(
      id: diskEvent.id,
      code: diskEvent.code,
      photoMode: diskEvent.photoMode,
      name: diskEvent.name,
      themeCount: diskEvent.themeCount,
      frameCount: diskEvent.frameCount,
      themeIds: diskEvent.themeIds,
      frameIds: diskEvent.frameIds,
    );
    return null;
  }
  // Backward compatibility for devices that only have the pre-v2 prefs.
  final cached = await eventManager.getEventCode();
  if (cached != null && cached == code) {
    return null;
  }
  return 'Invalid or inactive event code. Check with your venue and try again.';
}
