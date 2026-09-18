import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import '../../../utils/logger.dart';
import 'ingest_source.dart';
import 'platform_image_downscaler.dart';

/// Preview thumbnails for the import picker, decoded off the card.
///
/// The import screen is the one place with pictures to show and nothing on disk
/// to show them from: candidates are metadata until the operator commits, so the
/// only source is the card. Decoding those in Dart is not an option — a 24 MP
/// JPEG is seconds per frame on the Amlogic box — so this goes through the same
/// native channel the downscaler uses.
///
/// Natively the common path is MediaStore's own thumbnail cache, not a decode of
/// the original: the picker shows around sixty tiles at once, and reading sixty
/// 6 MB originals off an SD card to draw sixty 160 dp squares is what makes the
/// screen crawl. A real subsampled decode is the fallback for an unindexed card.
///
/// This is a preview of work **not yet done**, so it stays out of the pipeline's
/// way entirely: natively it runs on its own `preview` lane and takes no
/// large-bitmap permit, and nothing it produces is written to the ledger or to
/// disk. Scrolling the picker cannot slow an import that is already running, and
/// a thumbnail that fails to decode costs the candidate nothing — it still
/// imports.
///
/// Two limits keep a 3,000-frame card from taking the screen down, and both
/// matter on the weak boxes:
///
///  * **Concurrency.** Flinging a grid asks for hundreds of tiles in a frame or
///    two. Unbounded, the operator watches a screen of spinners resolve in
///    scroll order rather than in view order, long after the fling has settled.
///  * **Cache size.** Bytes are held so scrolling back is instant, but an
///    unbounded map is a slow leak that ends the night in an OOM. The cap is on
///    entries, which is sound because every entry is a bounded-size JPEG.
class IngestThumbnailer {
  IngestThumbnailer({
    MethodChannel? channel,
    this.shortSide = 256,
    this.maxConcurrent = 4,
    this.maxCached = 400,
  }) : _channel =
            channel ?? const MethodChannel(PlatformImageDownscaler.channelName);

  final MethodChannel _channel;

  /// Decoded short side. 256 covers a ~160 dp tile on a 1.5x screen.
  final int shortSide;

  /// How many decodes may be in flight at once. Matches the native `preview`
  /// lane's thread count — queueing more in Dart than the lane can run just
  /// moves the wait to the other side of the channel.
  final int maxConcurrent;

  /// How many decoded thumbnails to keep. ~20 KB each, so 400 is ~8 MB.
  final int maxCached;

  /// Insertion-ordered so the oldest key is the one evicted.
  final LinkedHashMap<String, Uint8List?> _cache =
      LinkedHashMap<String, Uint8List?>();

  /// In-flight requests, so two tiles asking for the same image decode once.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  int _running = 0;
  final Queue<_PendingThumb> _waiting = Queue<_PendingThumb>();
  bool _disposed = false;

  /// A thumbnail already in memory, or null if it has not been decoded yet.
  ///
  /// Lets a tile paint synchronously on a scroll-back instead of flashing a
  /// placeholder for a frame.
  Uint8List? cached(IngestCandidate candidate) => _cache[candidate.sourceRef];

  bool isCached(IngestCandidate candidate) =>
      _cache.containsKey(candidate.sourceRef);

  /// Decodes [candidate] to a small JPEG, or returns null when it cannot be
  /// decoded at all.
  ///
  /// A null is cached like any other answer: a card with a corrupt file must not
  /// retry it on every scroll past.
  Future<Uint8List?> thumbnail(IngestCandidate candidate) {
    final key = candidate.sourceRef;
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<Uint8List?>();
    _inFlight[key] = completer.future;
    _waiting.add(_PendingThumb(key, candidate.uri, completer));
    _pump();
    return completer.future;
  }

  void _pump() {
    while (!_disposed && _running < maxConcurrent && _waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      _running++;
      unawaited(_decode(next));
    }
  }

  Future<void> _decode(_PendingThumb pending) async {
    Uint8List? bytes;
    try {
      final raw = await _channel.invokeMethod<Uint8List>(
        'thumbnail',
        <String, Object?>{'uri': pending.uri, 'shortSide': shortSide},
      );
      bytes = (raw != null && raw.isNotEmpty) ? raw : null;
    } catch (e) {
      // Expected on web, in tests, and for a file the decoder cannot read. The
      // tile shows an icon; nothing about the import is blocked by it.
      AppLogger.debug('Ingest thumbnail failed for ${pending.uri}: $e');
      bytes = null;
    } finally {
      _running--;
      _inFlight.remove(pending.key);
    }
    _remember(pending.key, bytes);
    if (!pending.completer.isCompleted) pending.completer.complete(bytes);
    _pump();
  }

  void _remember(String key, Uint8List? bytes) {
    if (_disposed) return;
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > maxCached) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Drops everything held. Called when the screen goes, and when a rescan makes
  /// the previous card's thumbnails meaningless.
  void clear() {
    _cache.clear();
    _waiting.clear();
  }

  void dispose() {
    _disposed = true;
    for (final pending in _waiting) {
      if (!pending.completer.isCompleted) pending.completer.complete(null);
    }
    _waiting.clear();
    _inFlight.clear();
    _cache.clear();
  }
}

class _PendingThumb {
  _PendingThumb(this.key, this.uri, this.completer);

  final String key;
  final String uri;
  final Completer<Uint8List?> completer;
}
