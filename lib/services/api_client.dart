// Conditional import: use dart:io on mobile, create stub on web
// The transformImage method is only called on mobile (ApiService uses Dio directly on web)
import 'dart:io' if (dart.library.html) 'api_client_web_stub.dart' show File, Platform;
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/constants.dart';

part 'api_client.g.dart';

/// Error logger interface for retrofit generated code
abstract class ParseErrorLogger {
  void logError(Object error, StackTrace stackTrace, RequestOptions options, [dynamic response]);
}

@RestApi(baseUrl: AppConstants.kBaseUrl)
abstract class ApiClient {
  factory ApiClient(Dio dio, {String baseUrl}) = _ApiClient;

  /// Fetches available themes from the API
  @GET('/api/themes')
  Future<List<ThemeModel>> getThemes();

  /// Transforms an image using AI with the selected theme
  /// Note: This method is only used on mobile platforms.
  /// On web, ApiService uses Dio directly to handle file uploads.
  @POST('/ai-transform')
  @MultiPart()
  @DioResponseType(ResponseType.bytes)
  Future<List<int>> transformImage(
    @Part(name: 'prompt') String prompt,
    @Part(name: 'negative_prompt') String negativePrompt,
    @Part(name: 'image') File image,
  );

  /// Accepts terms and conditions (legacy endpoint)
  @POST('/accept-terms')
  Future<void> acceptTerms(
    @Body() Map<String, dynamic> body,
  );

  /// Accepts terms and creates a new session
  @POST('/api/sessions/accept-terms')
  Future<dynamic> acceptTermsAndCreateSession(
    @Body() Map<String, dynamic> body,
  );

  /// Updates session with user photo and selected theme
  @PATCH('/api/sessions/{sessionId}')
  Future<dynamic> updateSession(
    @Path('sessionId') String sessionId,
    @Body() Map<String, dynamic> body,
  );

  /// Generates transformed image using AI
  @POST('/api/generate-image')
  Future<dynamic> generateImage(
    @Body() Map<String, dynamic> body,
  );

  /// Preprocesses image (validation, compression, person detection)
  /// This is a fire-and-forget call - don't wait for completion
  @POST('/api/preprocess-image')
  Future<dynamic> preprocessImage(
    @Body() Map<String, dynamic> body,
  );
}

