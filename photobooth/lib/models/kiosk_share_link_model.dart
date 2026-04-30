class KioskShareLinkModel {
  final String token;
  final String url;
  final String? longUrl;
  final DateTime? expiresAt;

  const KioskShareLinkModel({
    required this.token,
    required this.url,
    this.longUrl,
    this.expiresAt,
  });

  factory KioskShareLinkModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return KioskShareLinkModel(
      token: (json['token'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      longUrl: json['longUrl']?.toString(),
      expiresAt: parseDate(json['expiresAt']),
    );
  }

  bool get isValid => token.trim().isNotEmpty && url.trim().isNotEmpty;
}

