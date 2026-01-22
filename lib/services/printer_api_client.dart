// Conditional import: use dart:io on mobile, create stub on web
import 'dart:io' if (dart.library.html) 'printer_api_client_web_stub.dart' show File, Platform;
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part 'printer_api_client.g.dart';

/// Error logger interface for retrofit generated code
abstract class ParseErrorLogger {
  void logError(Object error, StackTrace stackTrace, RequestOptions options, [dynamic response]);
}

/// Printer API client using Retrofit
/// Base URL is set dynamically based on printer IP
@RestApi()
abstract class PrinterApiClient {
  factory PrinterApiClient(Dio dio, {String? baseUrl, ParseErrorLogger? errorLogger}) = _PrinterApiClient;

  /// Prints an image to the network printer
  @POST('/api/PrintImage')
  @MultiPart()
  Future<void> printImage(
    @Part(name: 'imageFile') File imageFile,
    @Part(name: 'printSize') String printSize,
    @Part(name: 'quantity') int quantity,
    @Part(name: 'imageEdited') bool imageEdited,
    @Part(name: 'DeviceId') String deviceId,
  );
}
