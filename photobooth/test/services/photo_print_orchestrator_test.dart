import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/photo_print_orchestrator.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  group('throwIfNoPhotoPrinterSucceeded', () {
    test('allows when DNP succeeded', () {
      expect(
        () => throwIfNoPhotoPrinterSucceeded(
          dnpSucceeded: true,
          selphySucceeded: false,
          selphyError: PlatformException(code: 'NO_PRINTER'),
        ),
        returnsNormally,
      );
    });

    test('allows when Selphy succeeded', () {
      expect(
        () => throwIfNoPhotoPrinterSucceeded(
          dnpSucceeded: false,
          selphySucceeded: true,
          dnpError: PrintException('No DNP printer found'),
        ),
        returnsNormally,
      );
    });

    test('allows when both succeeded', () {
      expect(
        () => throwIfNoPhotoPrinterSucceeded(
          dnpSucceeded: true,
          selphySucceeded: true,
        ),
        returnsNormally,
      );
    });

    test('throws when neither succeeded', () {
      expect(
        () => throwIfNoPhotoPrinterSucceeded(
          dnpSucceeded: false,
          selphySucceeded: false,
          dnpError: PrintException('No DNP'),
          selphyError: PlatformException(code: 'NO_PRINTER', message: 'none'),
        ),
        throwsA(
          isA<PrintException>().having(
            (e) => e.message,
            'message',
            AppStrings.noPhotoPrinterConnected,
          ),
        ),
      );
    });
  });
}
