/// Phone normalization helpers for contact capture (E.164 / India defaults).
abstract final class ContactPhoneHelpers {
  static const defaultDialCode = '+91';

  /// E.164: leading '+' followed by 10–15 digits.
  static final RegExp e164 = RegExp(r'^\+\d{10,15}$');

  /// Strips spaces, dashes, parentheses, and dots. Keeps a leading '+'.
  /// If user enters a local number without country code, defaults to India.
  static String normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final compact = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
    if (compact.isEmpty) return '';

    if (compact.startsWith('+')) return compact;

    var digits = compact.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }

    if (digits.length == 10) {
      return '$defaultDialCode$digits';
    }

    return digits;
  }

  static bool isValidE164(String phone) => e164.hasMatch(phone);
}
