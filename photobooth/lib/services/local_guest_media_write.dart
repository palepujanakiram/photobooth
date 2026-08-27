import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:uuid/uuid.dart';

import 'image_cache_source.dart';
import 'local_media_store.dart';
import 'protected_image_loader.dart';

const kGuestMediaJpegExt = 'jpg';
const kFileUrlSchemePrefix = 'file://';

/// Test hook: skip disk IO (covers the web kiosk no-op path).
@visibleForTesting
bool debugForceSkipGuestMediaWrites = false;

/// Test hook: replace WAN fetch so unit tests never hit the network.
@visibleForTesting
Future<List<int>> Function(String url)? debugGuestMediaFetchBytes;

/// JPEG written under `fotozen_media/{prefix}/{uuid}.ext`.
class LocalGuestMediaWrite {
  const LocalGuestMediaWrite({required this.ref, required this.file});

  final LocalMediaRef ref;
  final File file;

  String get apiImgPath => guestMediaSessionUrl(ref);

  String get localMediaUri => '$kLocalMediaScheme://${ref.relativePath}';

  String get sessionUrl => apiImgPath;
}

String guestMediaSessionUrl(LocalMediaRef ref) =>
    '$kApiImgPathPrefix${ref.relativePath}';

bool _guestMediaWritesDisabled() =>
    kIsWeb || debugForceSkipGuestMediaWrites;

String _defaultNewId() => const Uuid().v4();

/// `{uuid}.jpg` under [prefix], or null when the prefix/filename is invalid.
LocalMediaRef? allocateGuestMediaRef({
  required String prefix,
  String ext = kGuestMediaJpegExt,
  String Function()? newId,
}) {
  final id = (newId ?? _defaultNewId)().trim();
  if (id.isEmpty) return null;
  var cleanExt = ext.trim();
  if (cleanExt.startsWith('.')) {
    cleanExt = cleanExt.substring(1);
  }
  if (cleanExt.isEmpty) return null;
  return LocalMediaRef.fromParts(prefix, '$id.$cleanExt');
}

/// Parses `{support}/fotozen_media/{prefix}/{file}` (and `file://` paths).
LocalMediaRef? guestMediaRefFromDiskPath(String path) {
  final normalized = _filePathFromUrl(path).replaceAll(r'\', '/');
  if (normalized.isEmpty) return null;
  const marker = '/$kFotozenMediaDirName/';
  final idx = normalized.indexOf(marker);
  if (idx >= 0) {
    return _refFromRelativeRest(normalized.substring(idx + marker.length));
  }
  if (normalized.startsWith('$kFotozenMediaDirName/')) {
    return _refFromRelativeRest(
      normalized.substring(kFotozenMediaDirName.length + 1),
    );
  }
  return _refFromRelativeRest(normalized);
}

LocalMediaRef? _refFromRelativeRest(String rest) {
  final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return LocalMediaRef.fromParts(parts[parts.length - 2], parts.last);
}

String? guestSessionUrlForPath(String path) {
  final ref = guestMediaRefFromDiskPath(path);
  if (ref == null) return null;
  return guestMediaSessionUrl(ref);
}

Future<List<int>> Function(String url) guestMediaNetworkFetch() {
  return debugGuestMediaFetchBytes ??
      ((url) => ProtectedImageLoader.instance.fetchBytes(url));
}

Future<LocalGuestMediaWrite?> putGuestJpeg({
  required String prefix,
  required List<int> bytes,
  LocalMediaStore? store,
  String Function()? newId,
  String ext = kGuestMediaJpegExt,
}) async {
  if (_guestMediaWritesDisabled() || bytes.isEmpty) return null;
  final ref = allocateGuestMediaRef(
    prefix: prefix,
    ext: ext,
    newId: newId,
  );
  if (ref == null) return null;
  final file = await (store ?? LocalMediaStore()).putBytes(ref, bytes);
  if (file == null) return null;
  return LocalGuestMediaWrite(ref: ref, file: file);
}

Future<LocalGuestMediaWrite?> putGuestJpegFromXFile({
  required String prefix,
  required XFile file,
  LocalMediaStore? store,
  String Function()? newId,
}) async {
  if (_guestMediaWritesDisabled()) return null;
  final media = store ?? LocalMediaStore();
  try {
    final existing = await _writeIfAlreadyOnDisk(file.path, media);
    if (existing != null) return existing;
    final bytes = await file.readAsBytes();
    return putGuestJpeg(
      prefix: prefix,
      bytes: bytes,
      store: media,
      newId: newId,
    );
  } catch (_) {
    return null;
  }
}

/// Copies a capture still into `user-uploads/{uuid}.jpg`. Returns [file] on skip/fail.
Future<XFile> persistCapturedGuestXFile(
  XFile file, {
  String prefix = kGuestMediaPrefixUserUploads,
  LocalMediaStore? store,
  String Function()? newId,
}) async {
  final written = await putGuestJpegFromXFile(
    prefix: prefix,
    file: file,
    store: store,
    newId: newId,
  );
  if (written == null) return file;
  return XFile(
    written.file.path,
    mimeType: 'image/jpeg',
    name: written.ref.filename,
  );
}

/// Copies [source] onto disk and returns `/api/img/{prefix}/{file}`.
///
/// Data URLs and local files need no WAN. Remote URLs use [fetchBytes] or
/// [guestMediaNetworkFetch]. Failures keep the original [source].
Future<String> persistGuestImageUrl({
  required String prefix,
  required String source,
  Future<List<int>> Function(String url)? fetchBytes,
  LocalMediaStore? store,
  String Function()? newId,
}) async {
  final trimmed = source.trim();
  if (_guestMediaWritesDisabled() || trimmed.isEmpty) return trimmed;
  final media = store ?? LocalMediaStore();
  final existing = await _writeIfAlreadyOnDisk(trimmed, media);
  if (existing != null) return existing.sessionUrl;
  final bytes = await _loadGuestSourceBytes(
    trimmed,
    fetchBytes ?? debugGuestMediaFetchBytes,
  );
  if (bytes == null || bytes.isEmpty) return trimmed;
  return _putLoadedGuestBytes(
    prefix: prefix,
    source: trimmed,
    bytes: bytes,
    store: media,
    newId: newId,
  );
}

/// Local store file or raw filesystem path for print/download. Null = WAN.
Future<XFile?> localXFileForGuestImage(
  String url, {
  LocalMediaStore? store,
}) async {
  if (_guestMediaWritesDisabled()) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  final stored = await (store ?? LocalMediaStore()).fileForUrl(trimmed);
  if (stored != null) return XFile(stored.path);
  if (_looksLikeRemoteOrVirtualUrl(trimmed)) return null;
  return _xFileIfExists(_filePathFromUrl(trimmed));
}

Future<LocalGuestMediaWrite?> _writeIfAlreadyOnDisk(
  String source,
  LocalMediaStore store,
) async {
  final ref =
      LocalMediaRef.parse(source) ?? guestMediaRefFromDiskPath(source);
  if (ref == null) return null;
  final file = await store.getFile(ref);
  if (file == null) return null;
  return LocalGuestMediaWrite(ref: ref, file: file);
}

Future<List<int>?> _loadGuestSourceBytes(
  String source,
  Future<List<int>> Function(String url)? fetchBytes,
) async {
  final dataUrl = extractInlineImageDataUrl(source);
  if (dataUrl != null) {
    return decodeInlineImageDataUrl(dataUrl);
  }
  if (!_looksLikeRemoteOrVirtualUrl(source)) {
    final fromFile = await _readLocalFileBytes(source);
    if (fromFile != null) return fromFile;
  }
  if (fetchBytes == null) return null;
  try {
    return await fetchBytes(source);
  } catch (_) {
    return null;
  }
}

Future<String> _putLoadedGuestBytes({
  required String prefix,
  required String source,
  required List<int> bytes,
  required LocalMediaStore store,
  String Function()? newId,
}) async {
  final known = LocalMediaRef.parse(source);
  if (known != null) {
    final file = await store.putBytes(known, bytes);
    if (file == null) return source;
    return guestMediaSessionUrl(known);
  }
  final written = await putGuestJpeg(
    prefix: prefix,
    bytes: bytes,
    store: store,
    newId: newId,
  );
  return written?.sessionUrl ?? source;
}

bool _looksLikeRemoteOrVirtualUrl(String source) {
  final lower = source.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return true;
  }
  if (lower.startsWith('data:')) return true;
  if (lower.startsWith('$kLocalMediaScheme:')) return true;
  if (source.contains(kApiImgPathPrefix)) return true;
  return false;
}

String _filePathFromUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.startsWith(kFileUrlSchemePrefix)) {
    return Uri.tryParse(trimmed)?.toFilePath() ?? trimmed;
  }
  return trimmed;
}

Future<List<int>?> _readLocalFileBytes(String source) async {
  try {
    final file = File(_filePathFromUrl(source));
    if (!await _isRegularFile(file.path)) return null;
    return file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<XFile?> _xFileIfExists(String path) async {
  if (path.isEmpty) return null;
  try {
    if (!await _isRegularFile(path)) return null;
    return XFile(path);
  } catch (_) {
    return null;
  }
}

Future<bool> _isRegularFile(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  return type == FileSystemEntityType.file;
}
