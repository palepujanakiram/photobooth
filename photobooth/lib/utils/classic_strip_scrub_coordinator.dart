import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/session_manager.dart';
import 'classic_strip_scrub_helpers.dart';
import 'logger.dart';

/// Per-shot Classic AF polish state for capture → look progress dots.
enum ClassicScrubDotStatus {
  /// Accepted; waiting in the serial scrub queue.
  pending,

  /// Gemini scrub in flight.
  scrubbing,

  /// Server reported cleaned.
  cleaned,

  /// Fail-open / skipped — look screen may retry.
  failed,
}

class _ScrubEntry {
  _ScrubEntry({required this.future});

  ClassicScrubDotStatus status = ClassicScrubDotStatus.pending;
  ClassicShotScrubResult? result;
  /// True after [ClassicStripScrubCoordinator.dropLast] — skip Gemini.
  bool abandoned = false;
  /// Completes as soon as the data URL is encoded (scrub may still run).
  final Completer<String> encodedReady = Completer<String>();
  final Future<ClassicShotScrubResult> future;
}

/// Survives Classic capture web remounts so per-shot scrub is not orphaned.
///
/// Web used to [pushReplacementNamed] between shots, wiping State futures and
/// deferring all polish to the look screen. This coordinator keeps the queue
/// and progress dots alive across that (and works when remount is skipped).
///
/// Client scrub POSTs stay serial; server applies downscale + batch concurrency.
class ClassicStripScrubCoordinator extends ChangeNotifier {
  ClassicStripScrubCoordinator._();

  static final ClassicStripScrubCoordinator instance =
      ClassicStripScrubCoordinator._();

  final List<_ScrubEntry> _entries = [];

  List<ClassicScrubDotStatus> get statuses =>
      _entries.map((e) => e.status).toList(growable: false);

  int get shotCount => _entries.length;

  /// Whether [index] is an accepted strip slot (may still be scrubbing).
  bool hasShot(int index) => index >= 0 && index < _entries.length;

  /// Start a new strip (call when opening capture with zero accepted shots).
  void reset() {
    _entries.clear();
    notifyListeners();
  }

  /// Drop last accepted shot (Retake last) and abandon its scrub future.
  ///
  /// Marks the entry abandoned so any in-flight / queued Gemini call is skipped
  /// when it reaches the serial gate (avoids starving shots 2–4 after retakes).
  void dropLast() {
    if (_entries.isEmpty) return;
    _entries.removeLast().abandoned = true;
    notifyListeners();
  }

  /// Forget failed capture scrubs so the look screen can re-POST those shots.
  ///
  /// Successful ([ClassicScrubDotStatus.cleaned]) slots are kept for adopt.
  void releaseFailedShots() {
    var changed = false;
    for (final e in _entries) {
      if (e.status != ClassicScrubDotStatus.failed) continue;
      e.abandoned = true;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Encode immediately, then queue Gemini scrub. Safe to call before retake.
  Future<ClassicShotScrubResult> enqueueShot({
    required Future<String> Function() encodeShotDataUrl,
    required bool enableScrub,
    ApiService? apiService,
    SessionManager? sessionManager,
  }) {
    final completer = Completer<ClassicShotScrubResult>();
    late final _ScrubEntry entry;
    entry = _ScrubEntry(future: completer.future);
    _entries.add(entry);
    notifyListeners();

    unawaited(
      _runShot(
        entry: entry,
        completer: completer,
        encodeShotDataUrl: encodeShotDataUrl,
        enableScrub: enableScrub,
        apiService: apiService,
        sessionManager: sessionManager,
      ),
    );
    return completer.future;
  }

  Future<void> _runShot({
    required _ScrubEntry entry,
    required Completer<ClassicShotScrubResult> completer,
    required Future<String> Function() encodeShotDataUrl,
    required bool enableScrub,
    ApiService? apiService,
    SessionManager? sessionManager,
  }) async {
    String? raw;
    try {
      entry.status = ClassicScrubDotStatus.scrubbing;
      notifyListeners();

      // Encode before retake / remount can invalidate the XFile.
      raw = await encodeShotDataUrl();
      _completeEncoded(entry, raw);

      if (entry.abandoned) {
        final result = ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
        completer.complete(result);
        return;
      }

      if (!enableScrub) {
        final result = ClassicShotScrubResult(dataUrl: raw, scrubbed: false);
        entry
          ..result = result
          ..status = ClassicScrubDotStatus.cleaned;
        notifyListeners();
        completer.complete(result);
        return;
      }

      final result = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => raw!,
        enableScrub: true,
        apiService: apiService,
        sessionManager: sessionManager,
        isCancelled: () => entry.abandoned,
      );
      if (entry.abandoned) {
        completer.complete(result);
        return;
      }
      entry
        ..result = result
        ..status = result.scrubbed
            ? ClassicScrubDotStatus.cleaned
            : ClassicScrubDotStatus.failed;
      notifyListeners();
      completer.complete(result);
    } catch (e, st) {
      AppLogger.warning(
        'Classic scrub coordinator shot failed (fail-open)',
        error: e,
        stackTrace: st,
      );
      _completeEncoded(entry, raw ?? '');
      final fallback = ClassicShotScrubResult(
        dataUrl: raw ?? '',
        scrubbed: false,
      );
      entry
        ..result = fallback
        ..status = ClassicScrubDotStatus.failed;
      notifyListeners();
      if (!completer.isCompleted) {
        completer.complete(fallback);
      }
    }
  }

  static void _completeEncoded(_ScrubEntry entry, String raw) {
    if (!entry.encodedReady.isCompleted) {
      entry.encodedReady.complete(raw);
    }
  }

  /// Await every accepted shot through Gemini (or fail-open). Prefer
  /// [awaitEncodedReady] when navigating off capture so scrub can finish on
  /// the look screen.
  Future<List<ClassicShotScrubResult>> awaitAll() async {
    final out = <ClassicShotScrubResult>[];
    for (final e in List<_ScrubEntry>.from(_entries)) {
      out.add(await e.future);
    }
    return out;
  }

  /// Await encode for each shot without waiting on Gemini.
  ///
  /// If scrub already finished for a shot, returns that result; otherwise
  /// returns the raw encode with [ClassicShotScrubResult.scrubbed] false.
  Future<List<ClassicShotScrubResult>> awaitEncodedReady() async {
    final out = <ClassicShotScrubResult>[];
    for (final e in List<_ScrubEntry>.from(_entries)) {
      final encoded = await e.encodedReady.future;
      final done = e.result;
      if (done != null) {
        out.add(done);
      } else {
        out.add(ClassicShotScrubResult(dataUrl: encoded, scrubbed: false));
      }
    }
    return out;
  }

  /// Await full scrub (or fail-open) for one accepted shot. Look screen uses
  /// this to adopt in-flight capture scrubs instead of starting a second POST.
  ///
  /// Returns null when the slot was abandoned (retake) or released after failure.
  Future<ClassicShotScrubResult?> awaitShotForAdopt(int index) async {
    if (!hasShot(index)) return null;
    final entry = _entries[index];
    if (entry.abandoned) return null;
    final result = await entry.future;
    if (entry.abandoned) return null;
    return result;
  }

  /// Await full scrub (or fail-open) for one accepted shot.
  Future<ClassicShotScrubResult> awaitShot(int index) {
    if (!hasShot(index)) {
      return Future.error(RangeError.index(index, _entries, 'index'));
    }
    return _entries[index].future;
  }

  /// Test-only.
  @visibleForTesting
  void resetForTests() {
    reset();
    ClassicStripScrubGate.resetForTests();
  }
}
