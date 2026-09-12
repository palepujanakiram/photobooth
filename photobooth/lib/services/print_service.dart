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
import 'dnp/dnp_print_image_prepare.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'photo_print_orchestrator.dart';
import 'selphy/selphy_print_bridge.dart';

class PrintService {
  PrintService({
    DnpPrintBridge? dnpPrintBridge,
    SelphyPrintBridge? selphyPrintBridge,
  })  : _dnpPrintBridge = dnpPrintBridge ?? DnpPrintBridge(),
        _selphyPrintBridge = selphyPrintBridge ?? SelphyPrintBridge();

  final DnpPrintBridge _dnpPrintBridge;
  final SelphyPrintBridge _selphyPrintBridge;

  Future<void> resetDnpPrintSession() async {
    await Future.wait([
      _dnpPrintBridge.resetSession(),
      _selphyPrintBridge.resetSession(),
    ]);
  }

  /// Guest/staff photo print entry point — DNP first, Selphy only if DNP fails.
  Future<void> printDnpPhoto(
    XFile imageFile, {
    AppSettingsModel? settings,
    required String printSize,
    int quantity = AppConstants.kDefaultPrintCopies,
  }) =>
      printImageSilent(
        imageFile,
        settings: settings,
        printSize: printSize,
        quantity: quantity,
      );

  /// Prints DNP first. Selphy runs only when DNP failed and [trySelphy] is true.
  ///
  /// Dual USB (DNP + Selphy SDK `getPrinterList`) on the same Android TV host
  /// ANRs the process. Event kiosks pass [trySelphy] false.
  /// Fails only when neither printer completes a job.
  Future<void> printImageSilent(
    XFile imageFile, {
    AppSettingsModel? settings,
    required String printSize,
    int quantity = AppConstants.kDefaultPrintCopies,
    bool trySelphy = true,
    bool prepareForDnp = true,
  }) async {
    // Sequential on purpose: both USB hosts on the same Android TV can freeze
    // if claimed together. Each path is independent otherwise.
    final dnp = await _printToDnp(
      imageFile,
      settings: settings,
      printSize: printSize,
      quantity: quantity,
      prepareForDnp: prepareForDnp,
    );
    if (!shouldAttemptSelphyPrint(
      trySelphy: trySelphy,
      dnpSucceeded: dnp.succeeded,
    )) {
      throwIfNoPhotoPrinterSucceeded(
        dnpSucceeded: dnp.succeeded,
        selphySucceeded: false,
        dnpError: dnp.error,
        selphyError: null,
      );
      return;
    }
    final selphy = await _printToSelphy(
      imageFile,
      printSize: printSize,
      quantity: quantity,
    );
    throwIfNoPhotoPrinterSucceeded(
      dnpSucceeded: dnp.succeeded,
      selphySucceeded: selphy.succeeded,
      dnpError: dnp.error,
      selphyError: selphy.error,
    );
  }

  Future<({bool succeeded, Object? error})> _printToDnp(
    XFile imageFile, {
    AppSettingsModel? settings,
    required String printSize,
    required int quantity,
    bool prepareForDnp = true,
  }) async {
    try {
      final prepared = prepareForDnp
          ? await prepareImageForDnpPrint(
              imageFile,
              networkPrintSize: printSize,
            )
          : imageFile;
      await _dnpPrintBridge.printImage(
        imageFile: prepared,
        settings: settings,
        networkPrintSize: printSize,
        quantity: quantity,
      );
      AppLogger.debug('DNP photo print succeeded');
      return (succeeded: true, error: null);
    } on PlatformException catch (e, stackTrace) {
      AppLogger.warning(
        'DNP print did not complete: ${e.code}',
        error: e,
        stackTrace: stackTrace,
      );
      return (succeeded: false, error: e);
    } on StateError catch (e, stackTrace) {
      AppLogger.warning('DNP print did not complete', error: e, stackTrace: stackTrace);
      return (succeeded: false, error: PrintException(e.message));
    } on PrintException catch (e, stackTrace) {
      AppLogger.warning('DNP print did not complete', error: e, stackTrace: stackTrace);
      return (succeeded: false, error: e);
    } catch (e, stackTrace) {
      AppLogger.warning('DNP print did not complete', error: e, stackTrace: stackTrace);
      return (succeeded: false, error: e);
    }
  }

  Future<({bool succeeded, Object? error})> _printToSelphy(
    XFile imageFile, {
    required String printSize,
    required int quantity,
  }) async {
    try {
      await _selphyPrintBridge.printImage(
        imageFile: imageFile,
        networkPrintSize: printSize,
        quantity: quantity,
      );
      AppLogger.debug('Canon Selphy photo print succeeded');
      return (succeeded: true, error: null);
    } on PlatformException catch (e, stackTrace) {
      AppLogger.warning(
        'Selphy print did not complete: ${e.code}',
        error: e,
        stackTrace: stackTrace,
      );
      return (succeeded: false, error: e);
    } on PrintException catch (e, stackTrace) {
      AppLogger.warning(
        'Selphy print did not complete',
        error: e,
        stackTrace: stackTrace,
      );
      return (succeeded: false, error: e);
    } catch (e, stackTrace) {
      AppLogger.warning(
        'Selphy print did not complete',
        error: e,
        stackTrace: stackTrace,
      );
      return (succeeded: false, error: e);
    }
  }

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
