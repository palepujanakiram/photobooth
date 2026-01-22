import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'dio_web_config_stub.dart' if (dart.library.html) 'dio_web_config.dart';
import 'api_logging_interceptor.dart';
import 'printer_api_client.dart';
import 'file_helper.dart';
import 'error_reporting/error_reporting_manager.dart';

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
      AppLogger.debug('❌ Print dialog error: $e');
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
      AppLogger.debug('⚠️ Error checking print availability: $e');
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
  Future<void> printImageToNetworkPrinter(XFile imageFile, {required String printerIp}) async {
    try {
      AppLogger.debug('🖨️ Starting network print to $printerIp...');
      ErrorReportingManager.log('🖨️ Network print initiated to $printerIp');
      
      await ErrorReportingManager.setCustomKeys({
        'print_method': 'network',
        'printer_ip': printerIp,
        'image_path': imageFile.path,
      });
      
      // Validate printer IP
      if (printerIp.isEmpty) {
        ErrorReportingManager.log('❌ Printer IP is empty');
        throw PrintException('Printer IP address is required');
      }

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
        downloadDio.interceptors.add(ApiLoggingInterceptor());
        
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
          baseUrl: 'http://$printerIp',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Accept-Encoding': 'gzip, deflate',
            'Accept-Language': 'en-IN,en;q=0.9,te-IN;q=0.8,te;q=0.7,en-GB;q=0.6,en-US;q=0.5',
            'Connection': 'keep-alive',
            'Origin': 'http://$printerIp',
            'Referer': 'http://$printerIp/print',
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          },
        ),
      );

      // Configure browser adapter for web
      configureDioForWeb(dio);
      
      // Add logging interceptor
      dio.interceptors.add(ApiLoggingInterceptor());

      // Create Retrofit client for printer API
      final printerClient = PrinterApiClient(dio, baseUrl: 'http://$printerIp', errorLogger: null);

      // Save image bytes to temp file for Retrofit (which expects File type)
      // On web, we'll use a workaround
      dynamic tempFile;
      if (kIsWeb) {
        // On web, we need to use Dio directly since Retrofit doesn't support web File well
        // But we'll still use the same Dio instance with logging
        final formData = FormData.fromMap({
          'ImageFile': MultipartFile.fromBytes(
            imageBytes,
            filename: 'image.jpg',
          ),
          'PrintSize': '4x6',
        });

        AppLogger.debug('🖨️ Sending print request to http://$printerIp/api/PrintImage');

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
        tempFile = FileHelper.createFile(filePath);
        await (tempFile as dynamic).writeAsBytes(imageBytes);

        AppLogger.debug('🖨️ Sending print request to http://$printerIp/api/PrintImage');

        try {
          // Use Retrofit to make the print request
          await printerClient.printImage(
            tempFile as dynamic,
            '4x6',
          );

          AppLogger.debug('✅ Print request sent successfully (mobile)');
          ErrorReportingManager.log('✅ Network print completed successfully (mobile)');
        } finally {
          // Clean up temp file
          if ((tempFile as dynamic).existsSync()) {
            await (tempFile as dynamic).delete();
          }
        }
      }
    } on DioException catch (e, stackTrace) {
      String errorMessage = 'Failed to print image';
      String errorType = 'unknown';
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorType = 'timeout';
        errorMessage = 'Connection to printer timed out. Please check the printer IP address.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorType = 'connection_error';
        errorMessage = 'Cannot connect to printer at $printerIp. Please check the IP address and network connection.';
      } else if (e.response != null) {
        errorType = 'http_error';
        errorMessage = 'Print request failed: ${e.response?.statusCode}';
        if (e.response?.data != null) {
          AppLogger.debug('Print error response: ${e.response?.data}');
        }
      } else {
        errorType = 'dio_error';
        errorMessage = 'Print request failed: ${e.message ?? "Unknown error"}';
      }
      
      AppLogger.debug('❌ Print error: $errorMessage');
      ErrorReportingManager.log('❌ Network print failed: $errorType - $errorMessage');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Network print failed: $errorType',
        extraInfo: {
          'error_type': errorType,
          'error_message': errorMessage,
          'printer_ip': printerIp,
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
      
      AppLogger.debug('❌ Unexpected print error: $e');
      ErrorReportingManager.log('❌ Unexpected network print error: $e');
      
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Unexpected print error',
        extraInfo: {
          'error': e.toString(),
          'printer_ip': printerIp,
          'image_path': imageFile.path,
        },
      );
      
      throw PrintException('Failed to print image: $e');
    }
  }
}

