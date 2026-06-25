import '../utils/constants.dart';
import '../utils/exceptions.dart';

/// IO/desktop stub — web session PATCH uses Dio in [ApiService.updateSession].
Future<String> patchSessionPhotoBodyOnWeb({
  required String sessionId,
  required String jsonBody,
  Duration timeout = AppConstants.kSessionUploadTimeout,
  Object? sessionManager,
  Object? client,
}) async {
  throw ApiException('patchSessionPhotoBodyOnWeb is web-only');
}
