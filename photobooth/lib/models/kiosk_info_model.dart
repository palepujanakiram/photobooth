class KioskInfoModel {
  final String id;
  final String code;
  final String? name;
  final String? location;
  final String? accountId;

  /// null=inherit, true=force ON, false=force OFF
  final bool? paymentEnabled;

  const KioskInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.location,
    this.accountId,
    this.paymentEnabled,
  });

  factory KioskInfoModel.fromJson(Map<String, dynamic> json) {
    final rawPayment = json['paymentEnabled'];
    bool? payment;
    if (rawPayment is bool) {
      payment = rawPayment;
    } else {
      payment = null;
    }

    return KioskInfoModel(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: json['name']?.toString(),
      location: json['location']?.toString(),
      accountId: json['accountId']?.toString(),
      paymentEnabled: payment,
    );
  }

  bool get isValid => id.trim().isNotEmpty && code.trim().isNotEmpty;
}

