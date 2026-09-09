import 'dart:io' show FileSystemException;

import 'package:flutter/services.dart' show PlatformException;

/// Why a single photo did not import.
enum IngestFailureKind {
  /// The photograph itself is at fault — truncated, undecodable, not really a
  /// JPEG. A real fault: the row stays `FAILED` so the operator can see it.
  item,

  /// The **source** went away underneath the import — the card was pulled, the
  /// reader unplugged, the volume unmounted. Nothing is wrong with the photo,
  /// so its row is rolled back and the run stops.
  sourceUnavailable,
}

/// Tells "the card is gone" apart from "this photo is bad".
///
/// The distinction is the whole of screens spec §9A. Recording a pulled card as
/// a per-photo failure is what turns a recoverable interruption into silent
/// loss: the tier-1 dedupe matches on every row regardless of stage, so a rescan
/// reports those photos as already imported and they become unreachable.
///
/// The native downscaler collapses every decode error into a single
/// `downscale_failed` code carrying the underlying message, so classification
/// has to read that message. The markers below are the ones Android produces
/// when a `content://` item's volume disappears; anything else is treated as the
/// photo's fault, which is the safe direction — a wrongly-`FAILED` photo is
/// visible and retryable, a wrongly-deleted row is only visible as a lie.
abstract final class IngestFailure {
  /// Substrings that mean the file or its volume is no longer reachable.
  static const List<String> _sourceGoneMarkers = <String>[
    'no such file',
    'not found',
    'filenotfound',
    'enoent',
    'enodev',
    'not mounted',
    'unmounted',
    'no such volume',
    'input/output error',
    'bad file descriptor',
    'has been unmounted',
  ];

  /// `errno` values that mean the medium went away rather than the file being
  /// bad: 2 `ENOENT`, 5 `EIO`, 19 `ENODEV`, 6 `ENXIO`.
  static const Set<int> _sourceGoneErrno = <int>{2, 5, 6, 19};

  static IngestFailureKind classify(Object error) {
    if (error is PlatformException) {
      return _fromText('${error.code} ${error.message ?? ''}');
    }
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code != null && _sourceGoneErrno.contains(code)) {
        return IngestFailureKind.sourceUnavailable;
      }
      return _fromText('${error.message} ${error.osError?.message ?? ''}');
    }
    return _fromText(error.toString());
  }

  /// True when the candidate cannot even be addressed — an empty URI, which is
  /// what a MediaStore row resolves to once its volume is gone.
  static bool isUnreachableUri(String uri) => uri.trim().isEmpty;

  static IngestFailureKind _fromText(String raw) {
    final text = raw.toLowerCase();
    for (final marker in _sourceGoneMarkers) {
      if (text.contains(marker)) return IngestFailureKind.sourceUnavailable;
    }
    return IngestFailureKind.item;
  }
}
