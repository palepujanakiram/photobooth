import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/event_pipeline/capture/event_capture_coordinator.dart';
import '../../services/event_pipeline/capture/event_capture_source.dart';
import '../../services/event_pipeline/capture/event_device_capture_uploader.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';

typedef EventStillPicker = Future<XFile?> Function();

/// Operator capture with this device's camera or a webcam.
///
/// The native Canon Activity is the event-box path. This is the phone/web
/// path: pick a still, review it, then queue it the same way a tethered frame
/// is queued — or upload it as an event-capture session when there is no
/// local ledger (web).
class EventDeviceCaptureViewModel extends ChangeNotifier {
  EventDeviceCaptureViewModel({
    EventCaptureCoordinator? coordinator,
    EventStillPicker? pickStill,
    EventDeviceCaptureUploader? uploader,
    EventDeviceCaptureUploader Function()? createUploader,
  })  : _coordinator = coordinator ?? EventCaptureCoordinator(),
        _pickStill = pickStill ?? _defaultPick,
        _uploader = uploader,
        _createUploader = createUploader ?? defaultUploader;

  final EventCaptureCoordinator _coordinator;
  final EventStillPicker _pickStill;
  final EventDeviceCaptureUploader? _uploader;
  final EventDeviceCaptureUploader Function() _createUploader;
  EventDeviceCaptureUploader? _createdUploader;

  CapturedShot? _pending;
  int _queued = 0;
  bool _busy = false;
  String? _message;

  CapturedShot? get pending => _pending;
  int get queuedCount => _queued;
  bool get isBusy => _busy;
  String? get message => _message;
  bool get hasPending => _pending != null;

  static Future<XFile?> _defaultPick() {
    return ImagePicker().pickImage(source: ImageSource.camera);
  }

  @visibleForTesting
  static EventDeviceCaptureUploader defaultUploader() =>
      EventDeviceCaptureUploader();

  EventDeviceCaptureUploader get _remote {
    return _uploader ?? (_createdUploader ??= _createUploader());
  }

  Future<void> shutter() async {
    if (_busy) return;
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final file = await _pickStill();
      if (file == null) return;
      _pending = await _shotFromPicked(file);
    } catch (e, st) {
      AppLogger.error('Device capture shutter failed', error: e, stackTrace: st);
      _message = AppStrings.eventDeviceCaptureNothing;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void retake() {
    _pending = null;
    _message = null;
    notifyListeners();
  }

  Future<CaptureCommitOutcome> accept() async {
    if (_busy) {
      return const CaptureCommitOutcome(queued: false, message: '');
    }
    final shot = _pending;
    if (shot == null) {
      return const CaptureCommitOutcome(
        queued: false,
        message: AppStrings.eventDeviceCaptureNothing,
      );
    }
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final outcome = await _commit(shot);
      _message = outcome.message;
      if (outcome.queued) {
        _queued++;
        _pending = null;
      }
      return outcome;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<CaptureCommitOutcome> _commit(CapturedShot shot) async {
    if (shot.originalPath.isNotEmpty && _coordinator.hasStorage) {
      return _coordinator.commitShot(shot);
    }
    final bytes = shot.inlineBytes ?? await _bytesFromPath(shot.originalPath);
    return _remote.upload(bytes, shot.fileName);
  }

  Future<CapturedShot?> _shotFromPicked(XFile file) async {
    final path = file.path;
    Uint8List? inline;
    var size = 0;
    if (path.isNotEmpty && !kIsWeb) {
      size = await _fileLength(path);
    }
    if (size == 0) {
      inline = await file.readAsBytes();
      size = inline.length;
    }
    if (size == 0) return null;
    return CapturedShot(
      originalPath: path,
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      bytes: size,
      inlineBytes: inline,
    );
  }

  Future<int> _fileLength(String path) async {
    try {
      return await File(path).length();
    } catch (e) {
      AppLogger.debug('Device capture file length failed: $e');
      return 0;
    }
  }

  Future<Uint8List> _bytesFromPath(String path) async {
    if (path.isEmpty) return Uint8List(0);
    try {
      return await File(path).readAsBytes();
    } catch (e) {
      AppLogger.debug('Device capture read failed: $e');
      return Uint8List(0);
    }
  }
}
