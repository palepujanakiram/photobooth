/// One row from Android [ApplicationExitInfo] (historical process death).
class AndroidProcessExit {
  const AndroidProcessExit({
    required this.timestampMs,
    required this.reason,
    this.reasonCode,
    this.status,
    this.description,
    this.importance,
    this.pssKb,
    this.rssKb,
  });

  final int timestampMs;
  final String reason;
  final int? reasonCode;
  final int? status;
  final String? description;
  final int? importance;
  final int? pssKb;
  final int? rssKb;

  /// LMK / crash / ANR / SIGKILL — not a clean user stop or self-exit.
  bool get isUnexpected => isUnexpectedAndroidProcessReason(reason);

  DateTime get occurredAt =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestampMs': timestampMs,
      'reason': reason,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (status != null) 'status': status,
      if (description != null) 'description': description,
      if (importance != null) 'importance': importance,
      if (pssKb != null) 'pssKb': pssKb,
      if (rssKb != null) 'rssKb': rssKb,
    };
  }

  Map<String, dynamic> toExtraInfo() {
    return <String, dynamic>{
      'android_exit_reason': reason,
      'android_exit_reason_code': reasonCode,
      'android_exit_status': status,
      'android_exit_description': description,
      'android_exit_importance': importance,
      'android_exit_pss_kb': pssKb,
      'android_exit_rss_kb': rssKb,
      'android_exit_at': occurredAt.toIso8601String(),
    };
  }

  static AndroidProcessExit? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      map[entry.key.toString()] = entry.value;
    }
    final timestampMs = _asInt(map['timestampMs']);
    final reason = map['reason']?.toString().trim() ?? '';
    if (timestampMs == null || timestampMs <= 0 || reason.isEmpty) {
      return null;
    }
    return AndroidProcessExit(
      timestampMs: timestampMs,
      reason: reason,
      reasonCode: _asInt(map['reasonCode']),
      status: _asInt(map['status']),
      description: map['description']?.toString(),
      importance: _asInt(map['importance']),
      pssKb: _asInt(map['pssKb']),
      rssKb: _asInt(map['rssKb']),
    );
  }

  static List<AndroidProcessExit> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <AndroidProcessExit>[];
    for (final item in raw) {
      final parsed = tryParse(item);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

/// Thrown when reporting a historical Android process death to Bugsnag.
class AndroidProcessExitException implements Exception {
  AndroidProcessExitException(this.reason);

  final String reason;

  @override
  String toString() => 'AndroidProcessExitException($reason)';
}

const _unexpectedAndroidProcessReasons = <String>{
  'LOW_MEMORY',
  'CRASH',
  'CRASH_NATIVE',
  'ANR',
  'SIGNALED',
  'EXCESSIVE_RESOURCE_USAGE',
  'INITIALIZATION_FAILURE',
  'DEPENDENCY_DIED',
  'OTHER',
  'UNKNOWN',
  'FREEZER',
};

/// Reasons that look like a booth "crash" to staff, not a clean stop.
bool isUnexpectedAndroidProcessReason(String reason) {
  return _unexpectedAndroidProcessReasons.contains(reason.trim().toUpperCase());
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
