import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../utils/logger.dart';

/// DSLR-style shutter feedback when a still is saved (native mobile / kiosk).
class CaptureSoundService {
  CaptureSoundService({
    this.enabled = !kIsWeb,
    AudioPlayer? player,
  }) : _playerOverride = player;

  @visibleForTesting
  final bool enabled;

  final AudioPlayer? _playerOverride;
  AudioPlayer? _player;
  bool _prepared = false;

  static const _shutterAsset = 'sounds/camera_shutter.wav';

  @visibleForTesting
  static const shutterVolume = 1.0;

  AudioPlayer get _playerInstance =>
      _playerOverride ?? (_player ??= AudioPlayer());

  bool get _hasPlayer => _playerOverride != null || _player != null;

  static AudioContext _captureAudioContext() => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      );

  /// Loads the shutter clip so playback is instant on capture.
  Future<void> warmUp() async {
    if (!enabled || _prepared) return;
    try {
      await _preparePlayer();
      _prepared = true;
    } catch (e, st) {
      AppLogger.error(
        'Capture shutter warm-up failed',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _preparePlayer() async {
    final player = _playerInstance;
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(shutterVolume);
    await player.setAudioContext(_captureAudioContext());
    await player.setSource(AssetSource(_shutterAsset));
  }

  /// Stops any in-flight shutter cue.
  Future<void> cancel() async {
    if (!enabled || !_hasPlayer) return;
    try {
      await _playerInstance.stop();
    } catch (_) {
      // Best-effort.
    }
  }

  /// DSLR-style shutter when a still is taken.
  Future<void> playShutter() async {
    if (!enabled) return;
    try {
      if (!_prepared) {
        await warmUp();
      }
      final player = _playerInstance;
      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e, st) {
      AppLogger.error(
        'Capture shutter replay failed; retrying from asset',
        error: e,
        stackTrace: st,
      );
      try {
        _prepared = false;
        await _preparePlayer();
        _prepared = true;
        await _playerInstance.resume();
      } catch (e2, st2) {
        AppLogger.error(
          'Capture shutter play failed',
          error: e2,
          stackTrace: st2,
        );
      }
    }
  }

  Future<void> dispose() async {
    await cancel();
    _prepared = false;
    if (!enabled || !_hasPlayer) return;
    await _playerInstance.dispose();
    _player = null;
  }
}
