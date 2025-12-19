import 'dart:io';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../screens/theme_selection/theme_model.dart';
import '../utils/constants.dart';

part 'api_client.g.dart';

@RestApi(baseUrl: AppConstants.kBaseUrl)
abstract class ApiClient {
  factory ApiClient(Dio dio, {String baseUrl}) = _ApiClient;

  /// Fetches available themes from the API
  @GET('/themes')
  Future<List<ThemeModel>> getThemes();

  /// Transforms an image using AI with the selected theme
  @POST('/ai-transform')
  @MultiPart()
  @DioResponseType(ResponseType.bytes)
  Future<List<int>> transformImage(
    @Part(name: 'prompt') String prompt,
    @Part(name: 'negative_prompt') String negativePrompt,
    @Part(name: 'image') File image,
  );

  /// Accepts terms and conditions
  @POST('/accept-terms')
  Future<void> acceptTerms(
    @Body() Map<String, dynamic> body,
  );
}

