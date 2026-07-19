/// Guest contact + DPDP marketing flags captured before Pay & Collect.
class CustomerContactCapture {
  const CustomerContactCapture({
    this.customerName = '',
    this.customerPhone = '',
    this.whatsappOptIn = false,
    this.customerEmail = '',
    this.marketingEmailOptIn = false,
    this.marketingSmsOptIn = false,
    this.marketingWhatsappOptIn = false,
    this.skipped = false,
  });

  final String customerName;
  final String customerPhone;

  /// Transactional WhatsApp receipt opt-in (requires non-empty phone).
  final bool whatsappOptIn;

  final String customerEmail;

  final bool marketingEmailOptIn;
  final bool marketingSmsOptIn;
  final bool marketingWhatsappOptIn;

  final bool skipped;

  static const empty = CustomerContactCapture();

  CustomerContactCapture copyWith({
    String? customerName,
    String? customerPhone,
    bool? whatsappOptIn,
    String? customerEmail,
    bool? marketingEmailOptIn,
    bool? marketingSmsOptIn,
    bool? marketingWhatsappOptIn,
    bool? skipped,
  }) {
    return CustomerContactCapture(
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      whatsappOptIn: whatsappOptIn ?? this.whatsappOptIn,
      customerEmail: customerEmail ?? this.customerEmail,
      marketingEmailOptIn: marketingEmailOptIn ?? this.marketingEmailOptIn,
      marketingSmsOptIn: marketingSmsOptIn ?? this.marketingSmsOptIn,
      marketingWhatsappOptIn:
          marketingWhatsappOptIn ?? this.marketingWhatsappOptIn,
      skipped: skipped ?? this.skipped,
    );
  }

  /// Map keys used when pushing route arguments.
  Map<String, dynamic> toRouteArgsMap() => {
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerWhatsappOptIn': whatsappOptIn,
        'customerEmail': customerEmail,
        'marketingEmailOptIn': marketingEmailOptIn,
        'marketingSmsOptIn': marketingSmsOptIn,
        'marketingWhatsappOptIn': marketingWhatsappOptIn,
      };

  static CustomerContactCapture tryParseRouteMap(Map args) {
    return CustomerContactCapture(
      customerName: args['customerName']?.toString() ?? '',
      customerPhone: args['customerPhone']?.toString() ?? '',
      whatsappOptIn: args['customerWhatsappOptIn'] == true,
      customerEmail: args['customerEmail']?.toString() ?? '',
      marketingEmailOptIn: args['marketingEmailOptIn'] == true,
      marketingSmsOptIn: args['marketingSmsOptIn'] == true,
      marketingWhatsappOptIn: args['marketingWhatsappOptIn'] == true,
    );
  }
}
