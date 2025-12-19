import 'dart:io';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/exceptions.dart';

class PrintService {
  /// Prints an image file
  Future<void> printImage(File imageFile) async {
    try {
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
}

