class TermsAcceptanceModel {
  final String deviceType;
  final bool accepted;

  const TermsAcceptanceModel({
    required this.deviceType,
    required this.accepted,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_type': deviceType,
      'accepted': accepted,
    };
  }
}

