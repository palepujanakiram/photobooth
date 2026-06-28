import '../utils/printer_endpoint.dart';
import 'print_service_helpers.dart';

/// Posts a print job to a LAN printer (native: Dio).
Future<void> postLanPrinterMultipart({
  required String baseUrl,
  required String apiPath,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
}) async {
  final dio = createPrinterApiDio(baseUrl);
  try {
    if (usesDnpMultipartPrintApi(apiPath)) {
      await postNetworkPrintMultipart(
        dio: dio,
        apiPath: apiPath,
        imageBytes: imageBytes,
        printSize: printSize,
        deviceId: deviceId,
      );
      return;
    }
    await postRawJpegNetworkPrint(
      dio: dio,
      apiPath: apiPath,
      imageBytes: imageBytes,
    );
  } finally {
    dio.close(force: true);
  }
}
