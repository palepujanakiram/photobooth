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

class PrintService {
  /// Prints an image file using the system print dialog
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> printImageWithDialog(XFile imageFile) async {
    try {
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
    } catch (e) {
      throw PrintException('Failed to print image: $e');
    }
  }

  /// Checks if printing is available
  Future<bool> canPrint() async {
    try {
      return await Printing.info().then((info) => info.canPrint);
    } catch (e) {
      return false;
    }
  }
  /// Prints an image file to a network printer via HTTP API (silent print)
  /// Works with XFile on all platforms (iOS, Android, Web)
  /// Handles both local files and HTTP/HTTPS URLs
  Future<void> printImageToNetworkPrinter(XFile imageFile, {required String printerIp}) async {
    try {
      // Validate printer IP
      if (printerIp.isEmpty) {
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

        AppLogger.debug('✅ Print request sent successfully');
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

          AppLogger.debug('✅ Print request sent successfully');
        } finally {
          // Clean up temp file
          if ((tempFile as dynamic).existsSync()) {
            await (tempFile as dynamic).delete();
          }
        }
      }
    } on DioException catch (e) {
      String errorMessage = 'Failed to print image';
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Connection to printer timed out. Please check the printer IP address.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'Cannot connect to printer at $printerIp. Please check the IP address and network connection.';
      } else if (e.response != null) {
        errorMessage = 'Print request failed: ${e.response?.statusCode}';
        if (e.response?.data != null) {
          AppLogger.debug('Print error response: ${e.response?.data}');
        }
      } else {
        errorMessage = 'Print request failed: ${e.message ?? "Unknown error"}';
      }
      
      AppLogger.debug('❌ Print error: $errorMessage');
      throw PrintException(errorMessage);
    } catch (e) {
      if (e is PrintException) {
        rethrow;
      }
      AppLogger.debug('❌ Unexpected print error: $e');
      throw PrintException('Failed to print image: $e');
    }
  }
}

