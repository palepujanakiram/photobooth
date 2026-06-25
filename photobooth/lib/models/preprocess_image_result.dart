/// Response from POST `/api/preprocess-image`.
class PreprocessImageResult {
  final bool success;
  final int? personCount;
  final Map<String, dynamic>? framing;

  const PreprocessImageResult({
    required this.success,
    this.personCount,
    this.framing,
  });

  factory PreprocessImageResult.fromJson(Map<String, dynamic> json) {
    int? personCount;
    final pc = json['personCount'];
    if (pc is int && pc > 0) {
      personCount = pc;
    } else if (pc is num && pc > 0) {
      personCount = pc.round();
    }

    Map<String, dynamic>? framing;
    final f = json['framing'];
    if (f is Map) {
      framing = Map<String, dynamic>.from(f);
    }

    return PreprocessImageResult(
      success: json['success'] == true,
      personCount: personCount,
      framing: framing,
    );
  }
}
