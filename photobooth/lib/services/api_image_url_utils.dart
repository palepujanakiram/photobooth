import '../utils/constants.dart';
import 'session_manager.dart';

/// Ensures URLs returned by the backend can be used by Dio.
String resolveApiImageUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final compact = trimmed.replaceAll(RegExp(r'\s+'), '');

  if (compact.startsWith('http://') || compact.startsWith('https://')) {
    return compact;
  }

  final base = Uri.parse(AppConstants.kBaseUrl);
  return base.resolve(compact).toString();
}

/// Adds session context for protected generated image endpoints when needed.
String withGeneratedImageSessionId(String url) {
  final sessionId = SessionManager().sessionId;
  if (sessionId == null || sessionId.isEmpty) return url;

  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (!uri.path.startsWith('/api/img/generated/')) return url;
  if (uri.queryParameters.containsKey('sessionId')) return url;

  final qp = Map<String, String>.from(uri.queryParameters);
  qp['sessionId'] = sessionId;
  return uri.replace(queryParameters: qp).toString();
}
