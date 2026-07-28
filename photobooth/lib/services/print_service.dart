import 'package:camera/camera.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import '../models/app_settings_model.dart';
import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'dnp/dnp_print_bridge.dart';
import 'error_reporting/error_reporting_manager.dart';

class PrintService {
  PrintService({DnpPrintBridge? dnpPrintBridge})
      : _dnpPrintBridge = dnpPrintBridge ?? DnpPrintBridge();

  final DnpPrintBridge _dnpPrintBridge;

  /// Silent print via DNP USB (Android) or WCM Plus Wi-Fi auto-discovery.
  Future<void> printImageSilent(
    XFile imageFile, {
    AppSettingsModel? settings,
    required String printSize,
    int quantity = AppConstants.kDefaultPrintCopies,
  }) async {
    try {
      await _dnpPrintBridge.printImage(
        imageFile: imageFile,
        settings: settings,
        networkPrintSize: printSize,
        quantity: quantity,
      );
    } on PlatformException catch (e, stackTrace) {
      AppLogger.error('DNP print platform error', error: e, stackTrace: stackTrace);
      throw PrintException(e.message ?? AppStrings.printFailedGeneric);
    } on StateError catch (e, stackTrace) {
      AppLogger.error('DNP print error', error: e, stackTrace: stackTrace);
      throw PrintException(e.message);
    }
  }

  void resetDnpPrintSession() => _dnpPrintBridge.resetSession();

  /// Prints an image file using the system print dialog
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> printImageWithDialog(XFile imageFile) async {
    try {
      AppLogger.debug('🖨️ Starting print dialog...');
      ErrorReportingManager.log('🖨️ Print dialog initiated');

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

      throw PrintException(AppStrings.printFailedGeneric);
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
}
