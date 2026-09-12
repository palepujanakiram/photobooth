import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/photo_print_orchestrator.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  group('shouldAttemptSelphyPrint', () {
    test('skips Selphy when DNP already printed', () {
      expect(
        shouldAttemptSelphyPrint(trySelphy: true, dnpSucceeded: true),
        isFalse,
      );
    });

    test('skips Selphy when the caller disabled it', () {
      expect(
        shouldAttemptSelphyPrint(trySelphy: false, dnpSucceeded: false),
        isFalse,
      );
    });

    test('tries Selphy only when DNP failed and it is enabled', () {
      expect(
        shouldAttemptSelphyPrint(trySelphy: true, dnpSucceeded: false),
        isTrue,
      );
    });
  });

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
