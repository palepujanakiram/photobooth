import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/local_invoice_number.dart';

void main() {
  test('boothInvoiceCode keeps full kiosk codes', () {
    expect(boothInvoiceCode('ODEON-01'), 'ODEON-01');
    expect(boothInvoiceCode('ODEON-02'), 'ODEON-02');
    expect(boothInvoiceCode('od-1'), 'OD-1');
    expect(boothInvoiceCode(null), 'GN');
    expect(boothInvoiceCode('  '), 'GN');
    expect(boothInvoiceCode('a'), 'AX');
    expect(boothInvoiceCode('!!'), 'GN');
  });

  test('indianFinancialYearCode uses Apr–Mar', () {
    expect(indianFinancialYearCode(DateTime(2026, 7, 17)), '2627');
    expect(indianFinancialYearCode(DateTime(2027, 3, 31)), '2627');
    expect(indianFinancialYearCode(DateTime(2027, 4, 1)), '2728');
  });

  test('formatInvoiceNumber and series key', () {
    expect(
      formatInvoiceNumber('ODEON-01', '2627', 147),
      'FZ/ODEON-01/2627/00147',
    );
    expect(
      formatInvoiceNumber('ODEON-01', 'xx', 0),
      'FZ/ODEON-01/0000/00001',
    );
    expect(
      formatInvoiceNumber('ODEON-01', '26270extra', 3),
      'FZ/ODEON-01/2627/00003',
    );
    expect(
      receiptSeriesKey('ODEON-01', DateTime(2026, 7, 17)),
      'ODEON-01/2627',
    );
    expect(
      parseKioskReceiptNumber('FZ/ODEON-01/2627/00147'),
      'FZ/ODEON-01/2627/00147',
    );
    expect(
      parseKioskReceiptNumber('  fz/odeon-01/2627/00001  '),
      'FZ/ODEON-01/2627/00001',
    );
    expect(parseKioskReceiptNumber(null), isNull);
    expect(parseKioskReceiptNumber(''), isNull);
    expect(parseKioskReceiptNumber('FZ/ODEON-01/2627/14'), isNull);
    expect(parseKioskReceiptNumber('INV-1'), isNull);
  });

  test('parseKioskInvoiceNumberParts extracts seq', () {
    expect(
      parseKioskInvoiceNumberParts('FZ/ODEON-01/2627/00147'),
      isA<ParsedKioskInvoiceNumber>()
          .having((p) => p.booth, 'booth', 'ODEON-01')
          .having((p) => p.fy, 'fy', '2627')
          .having((p) => p.seq, 'seq', 147),
    );
    expect(parseKioskInvoiceNumberParts('bad'), isNull);
  });

  test('truncates long kiosk codes', () {
    expect(
      boothInvoiceCode('ABCDEFGHIJKLMNOPQRST'),
      'ABCDEFGHIJKLMNOP',
    );
  });
}
