import '../utils/secure_image_url.dart';

class EventStationStats {
  final int captures;
  final int themePending;
  final int themeClaimed;
  final int themeDone;
  final int printPending;
  final int printClaimed;
  final int printDone;

  const EventStationStats({
    this.captures = 0,
    this.themePending = 0,
    this.themeClaimed = 0,
    this.themeDone = 0,
    this.printPending = 0,
    this.printClaimed = 0,
    this.printDone = 0,
  });

  factory EventStationStats.fromJson(Map<String, dynamic> json) {
    int n(String key) => _asInt(json[key]);
    return EventStationStats(
      captures: n('captures'),
      themePending: n('themePending'),
      themeClaimed: n('themeClaimed'),
      themeDone: n('themeDone'),
      printPending: n('printPending'),
      printClaimed: n('printClaimed'),
      printDone: n('printDone'),
    );
  }

  int get themeTotal => themePending + themeClaimed + themeDone;
  int get printTotal => printPending + printClaimed + printDone;
}

class EventCaptureStationItem {
  final String sessionId;
  final String status;
  final List<String> previewUrls;

  const EventCaptureStationItem({
    required this.sessionId,
    required this.status,
    this.previewUrls = const [],
  });

  factory EventCaptureStationItem.fromJson(Map<String, dynamic> json) {
    return EventCaptureStationItem(
      sessionId: (json['sessionId'] ?? json['id'] ?? '').toString(),
      status: _bucketStatus(json['status']),
      previewUrls: _stringList(json['previewUrls']),
    );
  }

  bool get isValid => sessionId.isNotEmpty && previewUrls.isNotEmpty;

  EventCaptureStationItem withStationImageAuth({
    required String kioskCode,
    required String eventCode,
  }) {
    return EventCaptureStationItem(
      sessionId: sessionId,
      status: status,
      previewUrls: [
        for (final url in previewUrls)
          stampEventStationImageUrl(
            url: url,
            sessionId: sessionId,
            kioskCode: kioskCode,
            eventCode: eventCode,
          ),
      ],
    );
  }
}

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
      status: _bucketStatus(src['status'] ?? json['status']),
      previewUrls: _stringList(json['previewUrls'] ?? src['previewUrls']),
    );
  }

  bool get isValid => id.isNotEmpty && sessionId.isNotEmpty;

  EventThemeStationJob withStationImageAuth({
    required String kioskCode,
    required String eventCode,
  }) {
    return EventThemeStationJob(
      id: id,
      sessionId: sessionId,
      status: status,
      previewUrls: [
        for (final url in previewUrls)
          stampEventStationImageUrl(
            url: url,
            sessionId: sessionId,
            kioskCode: kioskCode,
            eventCode: eventCode,
          ),
      ],
    );
  }
}

class EventPrintStationJob {
  final String id;
  final String sessionId;
  final String imageUrl;
  final String printSize;
  final String status;
  final bool canReissue;

  const EventPrintStationJob({
    required this.id,
    required this.sessionId,
    required this.imageUrl,
    this.printSize = 's4x6',
    this.status = 'PENDING',
    this.canReissue = false,
  });

  factory EventPrintStationJob.fromJson(Map<String, dynamic> json) {
    final nested = json['job'];
    final src = nested is Map
        ? Map<String, dynamic>.from(nested)
        : json;
    final size = (src['printSize'] ?? json['printSize'] ?? 's4x6').toString();
    final raw = (src['rawStatus'] ?? src['status'] ?? json['status'] ?? '').toString();
    final status = _bucketStatus(src['status'] ?? json['status'] ?? raw);
    return EventPrintStationJob(
      id: (src['id'] ?? json['id'] ?? '').toString(),
      sessionId: (src['sessionId'] ?? json['sessionId'] ?? '').toString(),
      imageUrl: (src['imageUrl'] ?? json['imageUrl'] ?? '').toString(),
      printSize: size.trim().isEmpty ? 's4x6' : size.trim(),
      status: status,
      canReissue: src['canReissue'] == true ||
          json['canReissue'] == true ||
          raw.toUpperCase() == 'FAILED' ||
          status == 'DONE' ||
          status == 'CLAIMED',
    );
  }

  bool get isValid => id.isNotEmpty && imageUrl.isNotEmpty;

  EventPrintStationJob withStationImageAuth({
    required String kioskCode,
    required String eventCode,
  }) {
    return EventPrintStationJob(
      id: id,
      sessionId: sessionId,
      imageUrl: stampEventStationImageUrl(
        url: imageUrl,
        sessionId: sessionId,
        kioskCode: kioskCode,
        eventCode: eventCode,
      ),
      printSize: printSize,
      status: status,
      canReissue: canReissue,
    );
  }
}

class EventStationBoard {
  final EventStationStats stats;
  final List<EventCaptureStationItem> captures;
  final List<EventThemeStationJob> themeJobs;
  final List<EventPrintStationJob> printJobs;

  const EventStationBoard({
    this.stats = const EventStationStats(),
    this.captures = const [],
    this.themeJobs = const [],
    this.printJobs = const [],
  });

  factory EventStationBoard.fromJson(dynamic data) {
    if (data is! Map) return const EventStationBoard();
    final map = Map<String, dynamic>.from(data);
    final statsRaw = map['stats'];
    return EventStationBoard(
      stats: statsRaw is Map
          ? EventStationStats.fromJson(Map<String, dynamic>.from(statsRaw))
          : const EventStationStats(),
      captures: _mapList(map['captures'], EventCaptureStationItem.fromJson)
          .where((e) => e.isValid)
          .toList(),
      themeJobs: parseEventThemeJobs(map),
      printJobs: parseEventPrintJobs(map),
    );
  }

  EventStationBoard withStationImageAuth({
    required String kioskCode,
    required String eventCode,
  }) {
    return EventStationBoard(
      stats: stats,
      captures: [
        for (final item in captures)
          item.withStationImageAuth(kioskCode: kioskCode, eventCode: eventCode),
      ],
      themeJobs: [
        for (final job in themeJobs)
          job.withStationImageAuth(kioskCode: kioskCode, eventCode: eventCode),
      ],
      printJobs: [
        for (final job in printJobs)
          job.withStationImageAuth(kioskCode: kioskCode, eventCode: eventCode),
      ],
    );
  }
}

const eventStationStatusBuckets = ['PENDING', 'CLAIMED', 'DONE'];

String stampEventStationImageUrl({
  required String url,
  required String sessionId,
  required String kioskCode,
  required String eventCode,
}) {
  return SecureImageUrl.withSessionId(
    url,
    sessionId: sessionId,
    kioskToken: '',
    kioskCode: kioskCode,
    eventCode: eventCode,
  );
}

List<T> itemsForStationStatus<T>(
  List<T> items,
  String status,
  String Function(T item) readStatus,
) {
  final wanted = status.trim().toUpperCase();
  return items.where((item) => readStatus(item).toUpperCase() == wanted).toList();
}

int stationStatusCount<T>(
  List<T> items,
  String status,
  String Function(T item) readStatus,
) {
  return itemsForStationStatus(items, status, readStatus).length;
}

List<String> captureCarouselUrls(List<EventCaptureStationItem> captures) {
  final out = <String>[];
  for (final item in captures) {
    for (final url in item.previewUrls) {
      if (!out.contains(url)) out.add(url);
    }
  }
  return out;
}

String _bucketStatus(dynamic raw) {
  final s = (raw ?? '').toString().trim().toUpperCase();
  if (s == 'PRINTING') return 'CLAIMED';
  if (s == 'SKIPPED') return 'DONE';
  if (s == 'FAILED') return 'PENDING';
  if (eventStationStatusBuckets.contains(s)) return s;
  return 'PENDING';
}

int _asInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

List<T> _mapList<T>(
  dynamic raw,
  T Function(Map<String, dynamic> json) parse,
) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList();
}

List<EventThemeStationJob> parseEventThemeJobs(dynamic data) {
  final list = _jobsList(data, 'themeJobs');
  return list
      .map(EventThemeStationJob.fromJson)
      .where((j) => j.isValid)
      .toList();
}

List<EventPrintStationJob> parseEventPrintJobs(dynamic data) {
  final list = _jobsList(data, 'printJobs');
  return list
      .map(EventPrintStationJob.fromJson)
      .where((j) => j.isValid)
      .toList();
}

List<Map<String, dynamic>> _jobsList(dynamic data, [String extraKey = 'jobs']) {
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (data is Map) {
    for (final key in [extraKey, 'jobs']) {
      final list = data[key];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
  }
  return const [];
}
