import '../utils/printer_endpoint.dart';
import 'print_service_helpers.dart';

/// Posts a print job to a LAN printer (native: Dio).
Future<void> postLanPrinterMultipart({
  required String baseUrl,
  required String apiPath,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
  int quantity = 1,
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
        quantity: quantity,
      );
      return;
    }
    // Raw JPEG endpoints have no quantity field — repeat the POST.
    final copies = quantity < 1 ? 1 : quantity;
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
