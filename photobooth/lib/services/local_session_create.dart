import 'package:uuid/uuid.dart';

import 'local_kiosk_models.dart';
import 'local_kiosk_store.dart';
import 'local_session_skeleton.dart';

class LocalSessionCreateResult {
  const LocalSessionCreateResult({
    required this.sessionJson,
    required this.usedLocalFallback,
  });

  final Map<String, dynamic> sessionJson;
  final bool usedLocalFallback;
}

/// Client UUID first, then Fly accept-terms. WAN-down still returns a local
/// session so classic cash/print can continue.
///
/// [forceOffline] (admin operating mode) still tries Fly when reachable so
/// AI/UPI work with Wi‑Fi; on any accept-terms failure it falls back to a
/// local skeleton instead of blocking the booth.
Future<LocalSessionCreateResult> createKioskSession({
  required Future<Map<String, dynamic>> Function(String clientId) acceptTerms,
  LocalKioskStore? store,
  String Function()? newId,
  String? kioskCode,
  DateTime? now,
  bool forceOffline = false,
  String? eventId,
}) async {
  final id = (newId ?? _uuidV4)();
  final local = localSessionSkeleton(id: id, now: now, eventId: eventId);
  await store?.upsertSession(
    LocalSessionWrite(id: id, payload: local, kioskCode: kioskCode),
  );
  try {
    final response = await acceptTerms(id);
    final remote = Map<String, dynamic>.from(response);
    if (eventId != null &&
        eventId.trim().isNotEmpty &&
        (remote['eventId']?.toString().trim().isEmpty ?? true)) {
      remote['eventId'] = eventId.trim();
    }
    final remoteId = (remote['id'] as String?)?.trim();
    final idToKeep = (remoteId != null && remoteId.isNotEmpty) ? remoteId : id;
    await store?.upsertSession(
      LocalSessionWrite(id: idToKeep, payload: remote, kioskCode: kioskCode),
    );
    return LocalSessionCreateResult(
      sessionJson: remote,
      usedLocalFallback: false,
    );
  } catch (e) {
    if (isWanDownSessionError(e) || forceOffline) {
      return LocalSessionCreateResult(
        sessionJson: local,
        usedLocalFallback: true,
      );
    }
    await store?.clearCurrentSession();
    rethrow;
  }
}

String _uuidV4() => const Uuid().v4();
