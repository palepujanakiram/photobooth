import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';
import '../utils/printer_endpoint.dart' show resolvePrinterApiPath;
import 'print_service_helpers.dart';

Uri _printerHttpBaseUri(String host, int port) {
  final h = host.trim();
  if (h.isEmpty) {
    throw ArgumentError('Printer host is required');
  }
  var p = port <= 0 ? 80 : port;
  if (p > 65535) {
    p = 80;
  }
  return Uri(
    scheme: 'http',
    host: h,
    port: p == 80 ? null : p,
  );
}

class PrintService {
  /// Prints an image file using the system print dialog
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> printImageWithDialog(XFile imageFile) async {
    try {
      AppLogger.debug('🖨️ Starting print dialog...');
      ErrorReportingManager.log('🖨️ Print dialog initiated');
      
      // Read bytes from XFile (works on all platforms)
      final imageBytes = await imageFile.readAsBytes();
      final doc = pw.Document();

      final image = pw.MemoryImage(imageBytes);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
      );
      
      AppLogger.debug('✅ Print dialog completed successfully');
      ErrorReportingManager.log('✅ Print dialog completed');
    } catch (e, stackTrace) {
      AppLogger.error('Print dialog error', error: e, stackTrace: stackTrace);
      ErrorReportingManager.log('❌ Print dialog failed: $e');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Print dialog failed',
        extraInfo: {
          'error': e.toString(),
          'image_path': imageFile.path,
        },
      );
      
      throw PrintException('Failed to print image: $e');
    }
  }

  /// Checks if printing is available
  Future<bool> canPrint() async {
    try {
      final canPrint = await Printing.info().then((info) => info.canPrint);
      AppLogger.debug('🖨️ Can print: $canPrint');
      return canPrint;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error checking print availability',
        error: e,
        stackTrace: stackTrace,
      );
      ErrorReportingManager.log('⚠️ Error checking print availability: $e');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Failed to check print availability',
        extraInfo: {
          'error': e.toString(),
        },
      );
      
      return false;
    }
  }
  /// Prints an image file to a network printer via HTTP API (silent print)
  /// Works with XFile on all platforms (iOS, Android, Web)
  /// Handles both local files and HTTP/HTTPS URLs
  Future<void> printImageToNetworkPrinter(
    XFile imageFile, {
    required String printerHost,
    int printerPort = 80,
    String? printerPath,
    String printSize = AppConstants.kPrintSizePortrait4x6,
  }) async {
    final host = printerHost.trim();
    final baseUri = _printerHttpBaseUri(host, printerPort);
    final baseUrl = baseUri.origin;
    final apiPath = resolvePrinterApiPath(printerPath);

    try {
      AppLogger.debug('🖨️ Starting network print to $baseUrl$apiPath...');
      ErrorReportingManager.log('🖨️ Network print initiated to $baseUrl$apiPath');

      await ErrorReportingManager.setCustomKeys({
        'print_method': 'network',
        'printer_host': host,
        'printer_port': printerPort.toString(),
        'printer_path': apiPath,
        'printer_base_url': baseUrl,
        'image_path': imageFile.path,
      });

      List<int> imageBytes;
      try {
        imageBytes = await loadImageBytesForNetworkPrint(imageFile);
      } on DioException catch (e, stackTrace) {
        final status = e.response?.statusCode;
        AppLogger.error(
          'Image download for print failed ($status)',
          error: e,
          stackTrace: stackTrace,
        );
        if (status == 403) {
          throw PrintException(
            'Cannot download your photo for printing (session unauthorized). '
            'Use Back to start and try the booth again.',
          );
        }
        throw PrintException(
          'Failed to download photo for printing (${status ?? "network error"})',
        );
      }
      if (imageBytes.isEmpty) {
        throw PrintException('Image file is empty');
      }

      final dio = createPrinterApiDio(baseUrl);

      final deviceId =
          kIsWeb ? 'flutter-photobooth-web' : 'flutter-photobooth-mobile';
      await postNetworkPrintMultipart(
        dio: dio,
        apiPath: apiPath,
        imageBytes: imageBytes,
        printSize: printSize,
        deviceId: deviceId,
      );
      ErrorReportingManager.log('✅ Network print completed successfully');
    } on DioException catch (e, stackTrace) {
      if (e.response?.data != null) {
        AppLogger.error(
          'Print error response: ${e.response?.data}',
          error: e,
          stackTrace: stackTrace,
        );
      }
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Network print failed',
        extraInfo: {
          'printer_base_url': baseUrl,
          'dio_error_type': e.type.toString(),
          'status_code': e.response?.statusCode?.toString() ?? 'none',
          'response_data': e.response?.data?.toString() ?? 'none',
        },
      );
      throwMappedNetworkPrintDioError(e, baseUrl);
    } catch (e, stackTrace) {
      if (e is PrintException) {
        rethrow;
      }
      
      AppLogger.error('Unexpected print error', error: e, stackTrace: stackTrace);
      ErrorReportingManager.log('❌ Unexpected network print error: $e');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Unexpected print error',
        extraInfo: {
          'error': e.toString(),
          'printer_base_url': baseUrl,
          'image_path': imageFile.path,
        },
      );
      
      throw PrintException('Failed to print image: $e');
    }
  }
}

