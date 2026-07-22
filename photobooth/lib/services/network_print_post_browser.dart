// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import '../utils/exceptions.dart';
import '../utils/logger.dart';
import '../utils/printer_endpoint.dart';

String _lanPrinterUrl(String baseUrl, String apiPath) {
  final path = apiPath.startsWith('/') ? apiPath : '/$apiPath';
  return '$baseUrl$path';
}

bool _isHttpsPagePostingToHttpPrinter(String printerUrl) {
  try {
    return html.window.location.protocol == 'https:' &&
        printerUrl.startsWith('http://');
  } catch (_) {
    return false;
  }
}

Future<void> _postMultipartNoCors({
  required String printerUrl,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
  int quantity = 1,
}) async {
  final blob = html.Blob([Uint8List.fromList(imageBytes)], 'image/jpeg');
  final form = html.FormData();
  form.appendBlob('imageFile', blob, 'image.jpg');
  form.append('printSize', printSize);
  form.append('quantity', '$quantity');
  form.append('imageEdited', 'false');
  form.append('DeviceId', deviceId);

  await html.window.fetch(printerUrl, <String, dynamic>{
    'method': 'POST',
    'body': form,
    'mode': 'no-cors',
  });
}

Future<void> _postRawJpegNoCors({
  required String printerUrl,
  required List<int> imageBytes,
}) async {
  final blob = html.Blob([Uint8List.fromList(imageBytes)], 'image/jpeg');
  await html.window.fetch(printerUrl, <String, dynamic>{
    'method': 'POST',
    'body': blob,
    'mode': 'no-cors',
  });
}

/// Posts a print job to a LAN printer (web: `fetch` with `no-cors`).
///
/// Printers on the LAN do not return CORS headers, so Dio/XHR preflight fails.
/// `/api/PrintImage` uses multipart (CORS-safelisted); `/print` and similar
/// endpoints expect a raw JPEG body (see zenai `server/lib/printer.ts`).
Future<void> postLanPrinterMultipart({
  required String baseUrl,
  required String apiPath,
  required List<int> imageBytes,
  required String printSize,
  required String deviceId,
  int quantity = 1,
}) async {
  final printerUrl = _lanPrinterUrl(baseUrl, apiPath);
  final multipart = usesDnpMultipartPrintApi(apiPath);
  final copies = quantity < 1 ? 1 : quantity;
  AppLogger.debug(
    '🖨️ Sending web no-cors ${multipart ? "multipart" : "raw JPEG"} '
    'print request to $printerUrl (qty=$copies)',
  );

  if (_isHttpsPagePostingToHttpPrinter(printerUrl)) {
    AppLogger.warning(
      'HTTPS page posting to HTTP LAN printer may be blocked by mixed content. '
      'Use the native kiosk app, serve the web kiosk over HTTP on the LAN, or '
      'launch Chrome with --allow-running-insecure-content.',
    );
  }

  try {
    if (multipart) {
      await _postMultipartNoCors(
        printerUrl: printerUrl,
        imageBytes: imageBytes,
        printSize: printSize,
        deviceId: deviceId,
        quantity: copies,
      );
    } else {
      for (var i = 0; i < copies; i++) {
        await _postRawJpegNoCors(
          printerUrl: printerUrl,
          imageBytes: imageBytes,
        );
      }
    }
    AppLogger.debug('✅ Web no-cors print request sent to $printerUrl');
  } catch (e, st) {
    AppLogger.error(
      'Web LAN print failed for $printerUrl',
      error: e,
      stackTrace: st,
    );
    final mixedContent = _isHttpsPagePostingToHttpPrinter(printerUrl);
    final message = mixedContent
        ? 'Cannot connect to printer at $baseUrl. HTTPS pages cannot POST to '
            'HTTP printers unless mixed content is allowed. Use the native app, '
            'serve the kiosk over HTTP on the LAN, or enable insecure content in Chrome.'
        : 'Cannot connect to printer at $baseUrl. Please check the address, '
            'port, and network connection.';
    throw PrintException(message);
  }
}
