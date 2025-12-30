import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:camera/camera.dart';
import '../utils/exceptions.dart';

class PrintService {
  /// Prints an image file
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> printImage(XFile imageFile) async {
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
}

