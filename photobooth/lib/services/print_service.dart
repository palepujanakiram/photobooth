import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'api_logging_interceptor.dart';
import 'alice_inspector.dart';
import 'printer_api_client.dart';
import 'file_helper.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'print_file.dart';

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
  }) async {
    final baseUri = _printerHttpBaseUri(printerHost, printerPort);
    final baseUrl = baseUri.origin;

    try {
      AppLogger.debug('🖨️ Starting network print to $baseUrl...');
      ErrorReportingManager.log('🖨️ Network print initiated to $baseUrl');

      await ErrorReportingManager.setCustomKeys({
        'print_method': 'network',
        'printer_host': printerHost.trim(),
        'printer_port': printerPort.toString(),
        'printer_base_url': baseUrl,
        'image_path': imageFile.path,
      });

      // Get image bytes - handle both local files and URLs
      List<int> imageBytes;
      final filePath = imageFile.path;
      
      // Check if the path is a URL (http:// or https://)
      if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        // Download the image from URL
        AppLogger.debug('📥 Downloading image from URL for printing: $filePath');
        final downloadDio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        configureDioForWeb(downloadDio);
        if (kDebugMode == true) {
          downloadDio.interceptors.add(ApiLoggingInterceptor());
          downloadDio.interceptors.add(AliceDioProxyInterceptor());
        }

        final response = await downloadDio.get<List<int>>(
          filePath,
          options: Options(responseType: ResponseType.bytes),
        );
        
        imageBytes = response.data ?? [];
        
        if (imageBytes.isEmpty) {
          throw PrintException('Downloaded image from URL is empty');
        }
        
        AppLogger.debug('✅ Downloaded ${imageBytes.length} bytes from URL');
      } else {
        // Read bytes from local file
        imageBytes = await imageFile.readAsBytes();
      }
      
      if (imageBytes.isEmpty) {
        throw PrintException('Image file is empty');
      }

      // Create Dio instance for printer API
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Accept-Encoding': 'gzip, deflate',
            'Accept-Language': 'en-IN,en;q=0.9,te-IN;q=0.8,te;q=0.7,en-GB;q=0.6,en-US;q=0.5',
            'Connection': 'keep-alive',
            'Origin': baseUrl,
            'Referer': '$baseUrl/print',
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          },
        ),
      );

      // Configure browser adapter for web
      configureDioForWeb(dio);
      
      if (kDebugMode == true) {
        dio.interceptors.add(ApiLoggingInterceptor());
        dio.interceptors.add(AliceDioProxyInterceptor());
      }

      // Create Retrofit client for printer API
      final printerClient = PrinterApiClient(dio, baseUrl: baseUrl, errorLogger: null);

      // Save image bytes to temp file for Retrofit (which expects File type)
      // On web, we'll use a workaround
      if (kIsWeb) {
        // On web, we need to use Dio directly since Retrofit doesn't support web File well
        // But we'll still use the same Dio instance with logging
        final formData = FormData.fromMap({
          'imageFile': MultipartFile.fromBytes(
            imageBytes,
            filename: 'image.jpg',
          ),
          'printSize': 's4x6',
          'quantity': 1,
          'imageEdited': false,
          'DeviceId': 'flutter-photobooth-web',
        });

        AppLogger.debug('🖨️ Sending print request to $baseUrl/api/PrintImage');

        await dio.post(
          '/api/PrintImage',
          data: formData,
          options: Options(contentType: 'multipart/form-data'),
        );

        AppLogger.debug('✅ Print request sent successfully (web)');
        ErrorReportingManager.log('✅ Network print completed successfully (web)');
        return;
      } else {
        // On mobile, save to temp file and use Retrofit
        final tempDirPath = await FileHelper.getTempDirectoryPath();
        final fileName = 'print_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = '$tempDirPath/$fileName';
        final PrintFile tempFile = createPrintFile(filePath);
        await tempFile.writeAsBytes(imageBytes);

        AppLogger.debug('🖨️ Sending print request to $baseUrl/api/PrintImage');

        try {
          // Use Retrofit to make the print request
          await printerClient.printImage(
            tempFile.retrofitFile,
            's4x6',
            1,
            false,
            'flutter-photobooth-mobile',
          );

          AppLogger.debug('✅ Print request sent successfully (mobile)');
          ErrorReportingManager.log('✅ Network print completed successfully (mobile)');
        } finally {
          // Clean up temp file
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
        }
      }
    } on DioException catch (e, stackTrace) {
      String errorMessage = 'Failed to print image';
      String errorType = 'unknown';
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorType = 'timeout';
        errorMessage =
            'Connection to printer timed out. Please check the printer address and port.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorType = 'connection_error';
        errorMessage =
            'Cannot connect to printer at $baseUrl. Please check the address, port, and network connection.';
      } else if (e.response != null) {
        errorType = 'http_error';
        errorMessage = 'Print request failed: ${e.response?.statusCode}';
        if (e.response?.data != null) {
          AppLogger.error(
            'Print error response: ${e.response?.data}',
            error: e,
            stackTrace: stackTrace,
          );
        }
      } else {
        errorType = 'dio_error';
        errorMessage = 'Print request failed: ${e.message ?? "Unknown error"}';
      }
      
      AppLogger.error('Print error: $errorMessage', error: e, stackTrace: stackTrace);
      ErrorReportingManager.log('❌ Network print failed: $errorType - $errorMessage');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Network print failed: $errorType',
        extraInfo: {
          'error_type': errorType,
          'error_message': errorMessage,
          'printer_base_url': baseUrl,
          'dio_error_type': e.type.toString(),
          'status_code': e.response?.statusCode?.toString() ?? 'none',
          'response_data': e.response?.data?.toString() ?? 'none',
        },
      );
      
      throw PrintException(errorMessage);
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

