import '../utils/printer_endpoint.dart';
import 'print_service_helpers.dart';

/// Posts a print job to a LAN printer (native: Dio).
///
/// Always issues one HTTP job per copy — many DNP/WCM firmwares ignore or
/// mishandle multipart `quantity` > 1.
Future<void> postLanPrinterMultipart({
  required String baseUrl,
  required String apiPath,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
  int quantity = 1,
}) async {
  final dio = createPrinterApiDio(baseUrl);
  final copies = quantity < 1 ? 1 : quantity;
  try {
    if (usesDnpMultipartPrintApi(apiPath)) {
      for (var i = 0; i < copies; i++) {
        await postNetworkPrintMultipart(
          dio: dio,
          apiPath: apiPath,
          imageBytes: imageBytes,
          printSize: printSize,
          deviceId: deviceId,
          quantity: 1,
        );
      }
      return;
    }
    for (var i = 0; i < copies; i++) {
      await postRawJpegNetworkPrint(
        dio: dio,
        apiPath: apiPath,
        imageBytes: imageBytes,
      );
    }
  } finally {
    dio.close(force: true);
  }
}
