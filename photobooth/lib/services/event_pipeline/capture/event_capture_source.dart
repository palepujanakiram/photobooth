import 'dart:io';
import 'dart:typed_data';

import '../../../models/event_pipeline/media_item.dart';
import '../../../utils/logger.dart';
import '../ingest/ingest_source.dart';

/// One frame off the camera, on disk and not yet committed to anything.
class CapturedShot {
  const CapturedShot({
    required this.originalPath,
    required this.capturedAtMs,
    this.previewPath,
    this.width = 0,
    this.height = 0,
    this.bytes = 0,
  });

  /// Untouched camera JPEG. Never decoded in Dart — a 6000×4000 frame is ~96 MB
  /// once decoded, which is the cost the whole pipeline exists to avoid.
  final String originalPath;

  /// Small copy for the review pane. Falls back to the original when the camera
  /// stack could not make one.
  final String? previewPath;

  final int capturedAtMs;
  final int width;
  final int height;
  final int bytes;

  String get displayPath => previewPath ?? originalPath;

  String get fileName {
    final i = originalPath.lastIndexOf('/');
    return i < 0 ? originalPath : originalPath.substring(i + 1);
  }
}

/// The camera behind the capture screen.
///
/// An abstraction rather than a direct call into the PTP service because this
/// screen has to work over three different stacks — tethered EDSDK, Direct PTP,
/// and CCAPI later — and the spec is explicit that CCAPI plugs in here without
/// the screen changing. It also lets the confirm/retake logic, which is the
/// part with real consequences, be tested without a camera.
abstract class EventCaptureSource {
  /// Model of the attached camera, or null when nothing is connected.
  Future<String?> cameraName();

  /// Fires the shutter and returns the frame, or null if nothing was taken.
  ///
  /// Never throws: a failure comes back as null with the reason logged, because
  /// a photographer mid-event needs the screen to stay usable more than they
  /// need a stack trace.
  Future<CapturedShot?> shoot();

  /// Releases the camera when the screen closes.
  Future<void> dispose();
}

/// Wraps one already-captured file so it imports exactly like a card photo.
///
/// This is what makes Confirm "queue into the same queue as card imports"
/// literally true rather than approximately: dedupe, downscale, thumbnail and
/// ledger row all come from the identical code path, so a captured frame cannot
/// drift from an imported one.
class CapturedShotSource implements IngestSource {
  CapturedShotSource(this.shot, {String? sourceId})
      : id = sourceId ?? 'camera';

  final CapturedShot shot;

  @override
  final String id;

  @override
  String get label => 'Camera';

  @override
  String get sourceKind => MediaSource.ptp;

  @override
  Future<List<IngestCandidate>> listAll() async {
    final file = File(shot.originalPath);
    if (!await file.exists()) return const <IngestCandidate>[];
    final stat = await file.stat();
    return <IngestCandidate>[
      IngestCandidate(
        sourceId: id,
        relativePath: shot.fileName,
        displayName: shot.fileName,
        sizeBytes: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        uri: shot.originalPath,
        capturedAtMs: shot.capturedAtMs,
        mimeType: 'image/jpeg',
        width: shot.width,
        height: shot.height,
      ),
    ];
  }

  @override
  Future<Uint8List> readRange(
    IngestCandidate candidate,
    int offset,
    int length,
  ) async {
    try {
      final handle = await File(candidate.uri).open();
      try {
        await handle.setPosition(offset);
        return await handle.read(length);
      } finally {
        await handle.close();
      }
    } catch (e) {
      AppLogger.debug('Capture readRange failed: $e');
      return Uint8List(0);
    }
  }
}
