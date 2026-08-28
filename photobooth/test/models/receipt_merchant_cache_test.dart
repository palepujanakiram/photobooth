import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/receipt_merchant_cache.dart';

void main() {
  test('address and cache round-trip including Map not Map<String,dynamic>', () {
    final address = ReceiptMerchantAddress.fromJson({
      'line1': '1 Main',
      'line2': 'Suite 2',
      'city': 'Hyderabad',
      'state': 'TG',
      'postalCode': '500001',
      'country': 'IN',
    });
    expect(address.toJson()['line1'], '1 Main');

    final cache = ReceiptMerchantCache.fromJson({
      'legalName': 'Legal Co',
      'displayName': 'Display',
      'cin': 'U1',
      'gstin': 'G1',
      'venueName': 'Mall',
      'placeOfSupply': 'TG',
      'address': <String, dynamic>{
        'line1': '1 Main',
        'city': 'Hyderabad',
      },
      'phone': '99',
      'email': 'a@b.c',
      'notes': 'Note',
      'kioskName': 'Lobby',
      'kioskCode': 'K1',
    });
    expect(cache.address?.line1, '1 Main');
    expect(cache.toJson()['legalName'], 'Legal Co');
    expect(cache.toJson()['address'], isA<Map>());
    expect(
      ReceiptMerchantCache.fromJson({
        'address': <dynamic, dynamic>{'line2': 'Suite'},
      }).address?.line2,
      'Suite',
    );

    expect(
      ReceiptMerchantCache.tryParse(<dynamic, dynamic>{'gstin': 'G2'})?.gstin,
      'G2',
    );
    expect(ReceiptMerchantCache.tryParse('nope'), isNull);
  });
}
