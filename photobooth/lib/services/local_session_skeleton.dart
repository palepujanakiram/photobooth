import 'dart:async';

import 'package:uuid/uuid.dart';

import '../utils/constants.dart';
import '../utils/exceptions.dart';

const Duration kLocalSessionTtl = Duration(hours: 24);

/// Persist this on the session payload when Fly is unreachable.
const kKioskSessionOfflineKey = 'offline';

const _heavySessionKeys = <String>['userImageUrl', 'compressedImageUrl'];

/// Session JSON the kiosk can use when Fly is unreachable.
Map<String, dynamic> localSessionSkeleton({
  required String id,
  DateTime? now,
  String? shareToken,
  String? eventId,
}) {
  final t = now ?? DateTime.now().toUtc();
  return <String, dynamic>{
    'id': id,
    'shareToken': shareToken ?? mintLocalShareToken(),
    if (eventId != null && eventId.trim().isNotEmpty) 'eventId': eventId.trim(),
    'termsAccepted': true,
    'termsAcceptedAt': t.toIso8601String(),
    'attemptsUsed': 0,
    'generatedImages': <dynamic>[],
    'expiresAt': t.add(kLocalSessionTtl).toIso8601String(),
    kKioskSessionOfflineKey: true,
  };
}

String mintLocalShareToken() => const Uuid().v4();

/// Drops capture blobs so SQLite/JSON never holds data-URL photos.
Map<String, dynamic> slimSessionPayload(Map<String, dynamic> payload) {
  final slim = Map<String, dynamic>.from(payload);
  for (final key in _heavySessionKeys) {
    slim.remove(key);
  }
  return slim;
}

/// True when accept-terms failed because WAN is down, not because the guest
/// was rejected (4xx).
bool isWanDownSessionError(Object error) {
  if (error is TimeoutException) return true;
  if (error is ApiException) {
    final code = error.statusCode;
    if (code == null) return true;
    if (code >= 500) return true;
    if (error.message == AppConstants.kErrorNetwork) return true;
    return false;
  }
  return false;
}
