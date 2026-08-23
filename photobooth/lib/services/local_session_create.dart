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
Future<LocalSessionCreateResult> createKioskSession({
  required Future<Map<String, dynamic>> Function(String clientId) acceptTerms,
  LocalKioskStore? store,
  String Function()? newId,
  String? kioskCode,
  DateTime? now,
}) async {
  final id = (newId ?? _uuidV4)();
  final local = localSessionSkeleton(id: id, now: now);
  await store?.upsertSession(
    LocalSessionWrite(id: id, payload: local, kioskCode: kioskCode),
  );
  try {
    final response = await acceptTerms(id);
    final remote = Map<String, dynamic>.from(response);
    final remoteId = (remote['id'] as String?)?.trim();
    final idToKeep =
        (remoteId != null && remoteId.isNotEmpty) ? remoteId : id;
    await store?.upsertSession(
      LocalSessionWrite(id: idToKeep, payload: remote, kioskCode: kioskCode),
    );
    return LocalSessionCreateResult(
      sessionJson: remote,
      usedLocalFallback: false,
    );
  } catch (e) {
    if (isWanDownSessionError(e)) {
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
