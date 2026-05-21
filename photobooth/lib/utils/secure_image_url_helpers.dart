/// Shared URL key scanning for [SecureImageUrl].
String? firstNonEmptyUrlFromMap(
  Map<String, dynamic> data,
  List<String> keys, {
  required String Function(String) absolutize,
}) {
  for (final key in keys) {
    final v = data[key];
    if (v is String && v.trim().isNotEmpty) {
      return absolutize(v.trim());
    }
  }
  return null;
}
