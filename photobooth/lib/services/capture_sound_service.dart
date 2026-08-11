import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../utils/logger.dart';

/// DSLR-style shutter feedback when a still is saved (native mobile / kiosk).
///
/// Android TV SoundPool is fdsan-sensitive: a second [AudioPlayer.dispose] /
/// unload on the same native sound aborts the process (`Sound::~Sound`).
/// Keep prepare/play/dispose single-flight and never dispose twice.
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
  bool _disposed = false;
  Future<void>? _op;

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

  Future<T> _serialize<T>(Future<T> Function() fn) async {
    final previous = _op;
    final gate = Completer<void>();
    _op = gate.future;
    try {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      return await fn();
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  /// Loads the shutter clip so playback is instant on capture.
  Future<void> warmUp() async {
    if (!enabled || _disposed || _prepared) return;
    await _serialize(() async {
      if (!enabled || _disposed || _prepared) return;
      try {
        await _preparePlayer();
        if (!_disposed) {
          _prepared = true;
        }
      } catch (e, st) {
        AppLogger.error(
          'Capture shutter warm-up failed',
          error: e,
          stackTrace: st,
        );
      }
    });
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
    if (!enabled || _disposed || !_hasPlayer) return;
    await _serialize(() async {
      if (!enabled || _disposed || !_hasPlayer) return;
      try {
        await _playerInstance.stop();
      } catch (_) {
        // Best-effort.
      }
    });
  }

  /// DSLR-style shutter when a still is taken.
  Future<void> playShutter() async {
    if (!enabled || _disposed) return;
    await _serialize(() async {
      if (!enabled || _disposed) return;
      try {
        if (!_prepared) {
          await _preparePlayer();
          if (_disposed) return;
          _prepared = true;
        }
        final player = _playerInstance;
        await player.stop();
        if (_disposed) return;
        await player.seek(Duration.zero);
        if (_disposed) return;
        await player.resume();
      } catch (e, st) {
        AppLogger.error(
          'Capture shutter replay failed; retrying from asset',
          error: e,
          stackTrace: st,
        );
        if (_disposed) return;
        try {
          _prepared = false;
          await _preparePlayer();
          if (_disposed) return;
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
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _prepared = false;
    await _serialize(() async {
      if (!_hasPlayer) return;
      final player = _player;
      _player = null;
      // Test override is owned by the caller — only stop, never dispose it.
      if (_playerOverride != null) {
        try {
          await _playerOverride!.stop();
        } catch (_) {}
        return;
      }
      if (player == null) return;
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (e, st) {
        AppLogger.warning(
          'Capture shutter dispose failed (ignored)',
          error: e,
          stackTrace: st,
        );
      }
    });
  }
}
