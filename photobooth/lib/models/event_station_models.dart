class EventThemeStationJob {
  final String id;
  final String sessionId;
  final String status;
  final List<String> previewUrls;

  const EventThemeStationJob({
    required this.id,
    required this.sessionId,
    required this.status,
    this.previewUrls = const [],
  });

  factory EventThemeStationJob.fromJson(Map<String, dynamic> json) {
    final nested = json['job'];
    final src = nested is Map
        ? Map<String, dynamic>.from(nested)
        : json;
    return EventThemeStationJob(
      id: (src['id'] ?? json['id'] ?? '').toString(),
      sessionId: (src['sessionId'] ?? json['sessionId'] ?? '').toString(),
      status: (src['status'] ?? json['status'] ?? '').toString(),
      previewUrls: _stringList(json['previewUrls'] ?? src['previewUrls']),
    );
  }

  bool get isValid => id.isNotEmpty && sessionId.isNotEmpty;
}

class EventPrintStationJob {
  final String id;
  final String sessionId;
  final String imageUrl;
  final String printSize;

  const EventPrintStationJob({
    required this.id,
    required this.sessionId,
    required this.imageUrl,
    this.printSize = 's4x6',
  });

  factory EventPrintStationJob.fromJson(Map<String, dynamic> json) {
    final nested = json['job'];
    final src = nested is Map
        ? Map<String, dynamic>.from(nested)
        : json;
    final size = (src['printSize'] ?? json['printSize'] ?? 's4x6').toString();
    return EventPrintStationJob(
      id: (src['id'] ?? json['id'] ?? '').toString(),
      sessionId: (src['sessionId'] ?? json['sessionId'] ?? '').toString(),
      imageUrl: (src['imageUrl'] ?? json['imageUrl'] ?? '').toString(),
      printSize: size.trim().isEmpty ? 's4x6' : size.trim(),
    );
  }

  bool get isValid => id.isNotEmpty && imageUrl.isNotEmpty;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

List<EventThemeStationJob> parseEventThemeJobs(dynamic data) {
  final list = _jobsList(data);
  return list
      .map(EventThemeStationJob.fromJson)
      .where((j) => j.isValid)
      .toList();
}

List<EventPrintStationJob> parseEventPrintJobs(dynamic data) {
  final list = _jobsList(data);
  return list
      .map(EventPrintStationJob.fromJson)
      .where((j) => j.isValid)
      .toList();
}

List<Map<String, dynamic>> _jobsList(dynamic data) {
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (data is Map && data['jobs'] is List) {
    return (data['jobs'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}
