class KioskInfoModel {
  final String id;
  final String code;
  final String? name;
  final String? location;
  final String? accountId;

  /// null=inherit, true=force ON, false=force OFF
  final bool? paymentEnabled;

  /// When false, kiosk skips Classic experience choice and goes straight to AI.
  /// Defaults to true when the API omits the field.
  final bool classicPhotosEnabled;

  /// Classic shot counts offered on the experience screen (1, 3, and/or 4).
  final List<int> classicShotModes;

  /// Per-kiosk guest price overrides (rupees). null = inherit account settings.
  final int? initialPrice;
  final int? additionalPrintPrice;
  final int? regenerationPrice;

  /// Admin guest network mode: `online` (default) or `offline`.
  final String operatingMode;

  /// High-water from Fly `receipt_invoice_sequences` for this booth's current FY.
  /// Used to keep the local counter ahead of cloud-issued invoices.
  final int? invoiceLastSeq;

  static const operatingModeOnline = 'online';
  static const operatingModeOffline = 'offline';

  const KioskInfoModel({
    required this.id,
    required this.code,
    this.name,
    this.location,
    this.accountId,
    this.paymentEnabled,
    this.classicPhotosEnabled = true,
    this.classicShotModes = const [1, 3, 4],
    this.initialPrice,
    this.additionalPrintPrice,
    this.regenerationPrice,
    this.operatingMode = operatingModeOnline,
    this.invoiceLastSeq,
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

    final rawClassic =
        json['classicPhotosEnabled'] ?? json['classic_photos_enabled'];
    // Missing/null → enabled (legacy kiosks / older API builds).
    final classicEnabled = _parseClassicPhotosEnabled(rawClassic);
    final modes = _parseClassicShotModes(
      json['classicShotModes'] ?? json['classic_shot_modes'],
    );

    return KioskInfoModel(
      id: (json['id'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      name: json['name']?.toString(),
      location: json['location']?.toString(),
      accountId: json['accountId']?.toString(),
      paymentEnabled: payment,
      classicPhotosEnabled: classicEnabled,
      classicShotModes: modes,
      initialPrice: parsePrice(json['initialPrice']),
      additionalPrintPrice: parsePrice(json['additionalPrintPrice']),
      regenerationPrice: parsePrice(json['regenerationPrice']),
      operatingMode: _parseOperatingMode(
        json['operatingMode'] ?? json['operating_mode'],
      ),
      invoiceLastSeq: parsePrice(json['invoiceLastSeq']),
    );
  }

  bool get isOperatingModeOffline => operatingMode == operatingModeOffline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        if (name != null) 'name': name,
        if (location != null) 'location': location,
        if (accountId != null) 'accountId': accountId,
        if (paymentEnabled != null) 'paymentEnabled': paymentEnabled,
        'classicPhotosEnabled': classicPhotosEnabled,
        'classicShotModes': classicShotModes,
        if (initialPrice != null) 'initialPrice': initialPrice,
        if (additionalPrintPrice != null)
          'additionalPrintPrice': additionalPrintPrice,
        if (regenerationPrice != null) 'regenerationPrice': regenerationPrice,
        'operatingMode': operatingMode,
        if (invoiceLastSeq != null) 'invoiceLastSeq': invoiceLastSeq,
      };

  /// Accepts bool, 0/1, and common string flags from admin/API payloads.
  static bool _parseClassicPhotosEnabled(dynamic raw) {
    if (raw == null) return true;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v.isEmpty) return true;
      if (v == 'false' || v == '0' || v == 'no' || v == 'off') return false;
      if (v == 'true' || v == '1' || v == 'yes' || v == 'on') return true;
    }
    // Unknown shape — prefer enabling Classic over silently hiding it.
    return raw != false;
  }

  static List<int> _parseClassicShotModes(dynamic raw) {
    if (raw is! List) return const [1, 3, 4];
    final seen = <int>{};
    for (final item in raw) {
      final n = item is int
          ? item
          : item is num
              ? item.round()
              : int.tryParse(item?.toString().trim() ?? '');
      if (n == 1 || n == 3 || n == 4) seen.add(n!);
    }
    if (seen.isEmpty) return const [1, 3, 4];
    return [1, 3, 4].where(seen.contains).toList();
  }

  /// Missing/unknown → online (legacy kiosks / older API builds).
  static String _parseOperatingMode(dynamic raw) {
    if (raw == true) return operatingModeOffline;
    if (raw == false) return operatingModeOnline;
    if (raw is num) {
      return raw != 0 ? operatingModeOffline : operatingModeOnline;
    }
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v == operatingModeOffline ||
          v == 'off' ||
          v == 'true' ||
          v == '1' ||
          v == 'yes') {
        return operatingModeOffline;
      }
    }
    return operatingModeOnline;
  }

  bool get isValid => id.trim().isNotEmpty && code.trim().isNotEmpty;
}
