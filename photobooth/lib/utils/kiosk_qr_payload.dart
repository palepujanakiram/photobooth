/// Encode/decode kiosk codes in QR payloads for phone ↔ booth scanning.
abstract final class KioskQrPayload {
  /// QR content the booth camera should scan (custom URI + query).
  static String encode(String kioskCode, {String? eventCode}) {
    final c = kioskCode.trim().toUpperCase();
    if (c.isEmpty) return '';
    final qp = <String, String>{'code': c};
    final event = eventCode?.trim().toUpperCase() ?? '';
    if (event.isNotEmpty) qp['event'] = event;
    return Uri(
      scheme: 'fotozen',
      host: 'kiosk',
      queryParameters: qp,
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

  /// Event code from a `fotozen://kiosk?...&event=` URI, or null.
  static String? parseEventCode(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'fotozen' ||
        uri.host.toLowerCase() != 'kiosk') {
      return null;
    }
    final event = (uri.queryParameters['event'] ??
            uri.queryParameters['eventCode'] ??
            '')
        .trim();
    if (event.isEmpty) return null;
    return event.toUpperCase();
  }
}
