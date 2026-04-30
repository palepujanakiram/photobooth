/// Encode/decode kiosk codes in QR payloads for phone ↔ booth scanning.
abstract final class KioskQrPayload {
  /// QR content the booth camera should scan (custom URI + query).
  static String encode(String kioskCode) {
    final c = kioskCode.trim().toUpperCase();
    if (c.isEmpty) return '';
    return Uri(
      scheme: 'fotozen',
      host: 'kiosk',
      queryParameters: {'code': c},
    ).toString();
  }

  /// Parses [raw] from a scanned QR or pasted text. Returns normalized code or null.
  static String? parse(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;

    final uri = Uri.tryParse(t);
    if (uri != null &&
        uri.scheme.toLowerCase() == 'fotozen' &&
        uri.host.toLowerCase() == 'kiosk') {
      final c = uri.queryParameters['code']?.trim();
      if (c != null && c.isNotEmpty) {
        return c.toUpperCase();
      }
    }

    // Plain token (alphanumeric + common separators), typical kiosk codes.
    final upper = t.toUpperCase();
    if (RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,62}$').hasMatch(upper)) {
      return upper;
    }
    return null;
  }
}
