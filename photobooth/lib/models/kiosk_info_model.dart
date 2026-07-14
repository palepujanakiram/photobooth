class KioskInfoModel {
  final String id;
  final String code;
  final String? name;
  final String? location;
  final String? accountId;

  /// null=inherit, true=force ON, false=force OFF
  final bool? paymentEnabled;

  /// Per-kiosk guest price overrides (rupees). null = inherit account settings.
  final int? initialPrice;
  final int? additionalPrintPrice;
  final int? regenerationPrice;

  const KioskInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.location,
    this.accountId,
    this.paymentEnabled,
    this.initialPrice,
    this.additionalPrintPrice,
    this.regenerationPrice,
  });

  factory KioskInfoModel.fromJson(Map<String, dynamic> json) {
    final rawPayment = json['paymentEnabled'];
    bool? payment;
    if (rawPayment is bool) {
      payment = rawPayment;
    } else {
      payment = null;
    }

    int? parsePrice(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
      return null;
    }

    return KioskInfoModel(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: json['name']?.toString(),
      location: json['location']?.toString(),
      accountId: json['accountId']?.toString(),
      paymentEnabled: payment,
      initialPrice: parsePrice(json['initialPrice']),
      additionalPrintPrice: parsePrice(json['additionalPrintPrice']),
      regenerationPrice: parsePrice(json['regenerationPrice']),
    );
  }

  bool get isValid => id.trim().isNotEmpty && code.trim().isNotEmpty;
}
