import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/printer_endpoint.dart';

void main() {
  group('resolvePrinterApiPath', () {
    test('empty or slash uses DNP default', () {
      expect(resolvePrinterApiPath(null), '/api/PrintImage');
      expect(resolvePrinterApiPath(''), '/api/PrintImage');
      expect(resolvePrinterApiPath('/'), '/api/PrintImage');
    });

    test('custom path is preserved', () {
      expect(resolvePrinterApiPath('/print'), '/print');
      expect(resolvePrinterApiPath('print'), '/print');
    });
  });

  group('resolvePrinterEndpoint', () {
    test('trims host and applies custom path', () {
      final endpoint = resolvePrinterEndpoint(
        AppSettingsModel(
          printerHost: '172.16.4.113 ',
          printerPort: 80,
          printerPath: '/print',
        ),
      );
      expect(endpoint.host, '172.16.4.113');
      expect(endpoint.port, 80);
      expect(endpoint.path, '/print');
      expect(endpoint.baseUrl, 'http://172.16.4.113');
    });

    test('falls back when settings missing', () {
      final endpoint = resolvePrinterEndpoint(null);
      expect(endpoint.host, AppConstants.kDefaultPrinterHost);
      expect(endpoint.path, '/api/PrintImage');
    });
  });
}
