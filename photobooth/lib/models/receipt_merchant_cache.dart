import '../utils/json_parse_helpers.dart';

/// Venue address block cached from `/api/settings` → `receiptMerchant`.
class ReceiptMerchantAddress {
  const ReceiptMerchantAddress({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  factory ReceiptMerchantAddress.fromJson(Map<String, dynamic> json) {
    return ReceiptMerchantAddress(
      line1: JsonParseHelpers.stringOrNull(json['line1']),
      line2: JsonParseHelpers.stringOrNull(json['line2']),
      city: JsonParseHelpers.stringOrNull(json['city']),
      state: JsonParseHelpers.stringOrNull(json['state']),
      postalCode: JsonParseHelpers.stringOrNull(json['postalCode']),
      country: JsonParseHelpers.stringOrNull(json['country']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (line1 != null) 'line1': line1,
        if (line2 != null) 'line2': line2,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (postalCode != null) 'postalCode': postalCode,
        if (country != null) 'country': country,
      };
}

/// GST / merchant header cached on the kiosk for offline tax invoices.
class ReceiptMerchantCache {
  const ReceiptMerchantCache({
    this.legalName,
    this.displayName,
    this.cin,
    this.gstin,
    this.venueName,
    this.placeOfSupply,
    this.address,
    this.phone,
    this.email,
    this.notes,
    this.gstRateBps = 1800,
    this.gstSplitMode = 'cgst_sgst',
    this.hsnSac = '998383',
    this.productName = 'FotoZen AI Photo Print',
    this.kioskName,
    this.kioskCode,
  });

  final String? legalName;
  final String? displayName;
  final String? cin;
  final String? gstin;
  final String? venueName;
  final String? placeOfSupply;
  final ReceiptMerchantAddress? address;
  final String? phone;
  final String? email;
  final String? notes;
  final int gstRateBps;
  final String gstSplitMode;
  final String hsnSac;
  final String productName;
  final String? kioskName;
  final String? kioskCode;

  String get merchantName {
    final legal = legalName?.trim() ?? '';
    if (legal.isNotEmpty) return legal;
    final display = displayName?.trim() ?? '';
    if (display.isNotEmpty) return display;
    return 'FotoZen.AI';
  }

  bool get hasGstin => (gstin?.trim() ?? '').isNotEmpty;

  factory ReceiptMerchantCache.fromJson(Map<String, dynamic> json) {
    final addrRaw = json['address'];
    ReceiptMerchantAddress? address;
    if (addrRaw is Map<String, dynamic>) {
      address = ReceiptMerchantAddress.fromJson(addrRaw);
    } else if (addrRaw is Map) {
      address = ReceiptMerchantAddress.fromJson(
        Map<String, dynamic>.from(addrRaw),
      );
    }
    final split = JsonParseHelpers.stringOrNull(json['gstSplitMode']) ??
        'cgst_sgst';
    return ReceiptMerchantCache(
      legalName: JsonParseHelpers.stringOrNull(json['legalName']),
      displayName: JsonParseHelpers.stringOrNull(json['displayName']),
      cin: JsonParseHelpers.stringOrNull(json['cin']),
      gstin: JsonParseHelpers.stringOrNull(json['gstin']),
      venueName: JsonParseHelpers.stringOrNull(json['venueName']),
      placeOfSupply: JsonParseHelpers.stringOrNull(json['placeOfSupply']),
      address: address,
      phone: JsonParseHelpers.stringOrNull(json['phone']),
      email: JsonParseHelpers.stringOrNull(json['email']),
      notes: JsonParseHelpers.stringOrNull(json['notes']),
      gstRateBps: JsonParseHelpers.intOrNull(json['gstRateBps']) ?? 1800,
      gstSplitMode: split == 'igst' ? 'igst' : 'cgst_sgst',
      hsnSac: JsonParseHelpers.stringOrNull(json['hsnSac']) ?? '998383',
      productName: JsonParseHelpers.stringOrNull(json['productName']) ??
          'FotoZen AI Photo Print',
      kioskName: JsonParseHelpers.stringOrNull(json['kioskName']),
      kioskCode: JsonParseHelpers.stringOrNull(json['kioskCode']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (legalName != null) 'legalName': legalName,
        if (displayName != null) 'displayName': displayName,
        if (cin != null) 'cin': cin,
        if (gstin != null) 'gstin': gstin,
        if (venueName != null) 'venueName': venueName,
        if (placeOfSupply != null) 'placeOfSupply': placeOfSupply,
        if (address != null) 'address': address!.toJson(),
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (notes != null) 'notes': notes,
        'gstRateBps': gstRateBps,
        'gstSplitMode': gstSplitMode,
        'hsnSac': hsnSac,
        'productName': productName,
        if (kioskName != null) 'kioskName': kioskName,
        if (kioskCode != null) 'kioskCode': kioskCode,
      };

  static ReceiptMerchantCache? tryParse(Object? raw) {
    if (raw is Map<String, dynamic>) return ReceiptMerchantCache.fromJson(raw);
    if (raw is Map) {
      return ReceiptMerchantCache.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }
}
