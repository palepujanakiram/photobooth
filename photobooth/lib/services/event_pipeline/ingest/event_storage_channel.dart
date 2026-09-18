import 'package:flutter/services.dart';

import '../../../utils/logger.dart';

/// A removable volume as the platform reports it.
class ExternalVolume {
  const ExternalVolume({
    required this.uuid,
    required this.description,
    required this.isRemovable,
    required this.isIndexed,
    this.path,
    this.mediaStoreVolumeName,
    this.directRead = false,
    this.state,
    this.totalBytes,
  });

  final String uuid;
  final String description;
  final bool isRemovable;

  /// True when MediaStore has a volume by this name — i.e. it can be enumerated.
  ///
  /// A volume that is mounted but **not** indexed must be surfaced as such, or an
  /// unreadable card looks identical to an empty one.
  final bool isIndexed;

  final String? path;
  final String? mediaStoreVolumeName;

  /// Whether the app UID can enumerate the volume with plain `File` APIs.
  ///
  /// Measured false on Android 13 even holding sdcard_rw — direct access to a
  /// removable volume needs MANAGE_EXTERNAL_STORAGE, which is Play-restricted.
  final bool directRead;

  final String? state;

  /// Capacity of the volume, or null when it could not be stat-ed.
  ///
  /// On the picker this is how an operator tells two seated cards apart: a UUID
  /// is not something anyone recognises, but "64 GB" and "119 GB" are.
  final int? totalBytes;

  bool get isUsable => isRemovable && isIndexed && mediaStoreVolumeName != null;

  /// What the picker calls this card, e.g. `SD card 2609-0353`.
  ///
  /// The UUID is included because two cards from the same reader carry the same
  /// description, and the operator has to be able to say which row is which.
  String get displayLabel {
    final desc = description.trim();
    final id = uuid.trim();
    if (desc.isEmpty) return id.isEmpty ? 'Card' : id;
    if (id.isEmpty) return desc;
    return '$desc $id';
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  static ExternalVolume fromMap(Map<Object?, Object?> map) {
    return ExternalVolume(
      uuid: (map['uuid'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      isRemovable: map['isRemovable'] == true,
      isIndexed: map['isIndexed'] == true,
      path: map['path'] as String?,
      mediaStoreVolumeName: map['mediaStoreVolumeName'] as String?,
      directRead: map['directRead'] == true,
      state: map['state'] as String?,
      totalBytes: _int(map['totalBytes']),
    );
  }
}

/// Platform bridge for volume discovery and MediaStore enumeration.
class EventStorageChannel {
  EventStorageChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.srisarani.fotozenai/event_storage';

  final MethodChannel _channel;

  /// Removable volumes, with whether each is MediaStore-indexed.
  Future<List<ExternalVolume>> listVolumes() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('listVolumes');
      if (raw == null) return const <ExternalVolume>[];
      return [
        for (final entry in raw)
          if (entry is Map<Object?, Object?>) ExternalVolume.fromMap(entry),
      ];
    } on PlatformException catch (e) {
      AppLogger.warning('listVolumes failed: ${e.message}');
      return const <ExternalVolume>[];
    } on MissingPluginException {
      return const <ExternalVolume>[];
    }
  }

  /// Every image MediaStore holds for [volumeName], optionally folder-filtered.
  ///
  /// One cursor, no directory walk — the folder list and counts the review screen
  /// shows are derived from this same result rather than a second pass.
  Future<List<Map<Object?, Object?>>> queryImages({
    required String volumeName,
    List<String>? folders,
  }) async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('queryImages', {
        'volumeName': volumeName,
        if (folders != null) 'folders': folders,
      });
      if (raw == null) return const <Map<Object?, Object?>>[];
      return [
        for (final entry in raw)
          if (entry is Map<Object?, Object?>) entry,
      ];
    } on PlatformException catch (e) {
      AppLogger.warning('queryImages failed: ${e.message}');
      return const <Map<Object?, Object?>>[];
    } on MissingPluginException {
      return const <Map<Object?, Object?>>[];
    }
  }

  /// Reads a window of an item, for the content-key samples.
  Future<Uint8List> readRange(String uri, int offset, int length) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readRange', {
        'uri': uri,
        'offset': offset,
        'length': length,
      });
      return bytes ?? Uint8List(0);
    } on PlatformException catch (e) {
      AppLogger.warning('readRange failed for $uri: ${e.message}');
      return Uint8List(0);
    } on MissingPluginException {
      return Uint8List(0);
    }
  }

  /// Free bytes on the volume holding [path], or null when unavailable.
  Future<int?> freeBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The Phase 1 storage probe, for re-measuring on unfamiliar hardware.
  ///
  /// Kept because the mechanism was settled on a phone, not the Amlogic box:
  /// `vold` and MediaProvider behaviour there still needs confirming.
  Future<Map<Object?, Object?>> probeStorage() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('probeStorage');
      return raw ?? const <Object?, Object?>{};
    } on PlatformException catch (e) {
      AppLogger.warning('probeStorage failed: ${e.message}');
      return const <Object?, Object?>{};
    } on MissingPluginException {
      return const <Object?, Object?>{};
    }
  }
}
