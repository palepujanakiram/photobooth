/// A frame overlay cached on device for an event.
///
/// Frames are fetched and downloaded **while WAN is available**, then composited
/// entirely offline. That is what lets an AI-off event finish its whole chain
/// with no network — and why a frame-enabled event that goes offline without
/// cached frames has to be caught before a batch is queued rather than failing
/// four hundred items one at a time.
class EventFrame {
  const EventFrame({
    required this.id,
    required this.eventId,
    required this.overlayUrl,
    this.name,
    this.localPath,
    this.width,
    this.height,
    this.downloadedAtMs,
  });

  final String id;
  final String eventId;

  /// Remote source. Kept so a re-download can be retried after a failure.
  final String overlayUrl;

  final String? name;

  /// Path in the event media store. Null until the PNG has been downloaded —
  /// which is exactly the distinction [isCached] exists to express.
  final String? localPath;

  final int? width;
  final int? height;
  final int? downloadedAtMs;

  /// True once the overlay bytes are on disk and framing can run offline.
  bool get isCached => (localPath?.trim().isNotEmpty ?? false);

  EventFrame copyWith({
    String? localPath,
    int? width,
    int? height,
    int? downloadedAtMs,
  }) {
    return EventFrame(
      id: id,
      eventId: eventId,
      overlayUrl: overlayUrl,
      name: name,
      localPath: localPath ?? this.localPath,
      width: width ?? this.width,
      height: height ?? this.height,
      downloadedAtMs: downloadedAtMs ?? this.downloadedAtMs,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'event_id': eventId,
        'name': name,
        'overlay_url': overlayUrl,
        'local_path': localPath,
        'width': width,
        'height': height,
        'downloaded_at_ms': downloadedAtMs,
      };

  factory EventFrame.fromRow(Map<String, Object?> row) {
    return EventFrame(
      id: (row['id'] ?? '').toString(),
      eventId: (row['event_id'] ?? '').toString(),
      overlayUrl: (row['overlay_url'] ?? '').toString(),
      name: row['name'] as String?,
      localPath: row['local_path'] as String?,
      width: row['width'] as int?,
      height: row['height'] as int?,
      downloadedAtMs: row['downloaded_at_ms'] as int?,
    );
  }
}

/// Whether an event's frames are ready to composite offline.
class FrameCacheStatus {
  const FrameCacheStatus({
    required this.total,
    required this.cached,
    required this.selectedIsCached,
  });

  final int total;
  final int cached;

  /// Whether the frame the config actually names is on disk. This, not [total],
  /// is what gates a frame-enabled batch.
  final bool selectedIsCached;

  bool get isEmpty => total == 0;
  bool get allCached => total > 0 && cached == total;

  String get summary {
    if (total == 0) return 'No frames for this event';
    if (cached == total) return 'Frames ready — $cached cached';
    return 'Frames incomplete — $cached of $total downloaded';
  }
}
