import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';

/// Helper function to check if running on iOS
/// Works on all platforms including web
bool get _isIOS {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Helper function to check if running on Android
/// Works on all platforms including web
bool get _isAndroid {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// Custom camera controller that uses platform channel to select cameras by device ID
/// This bypasses the Flutter camera package's lensDirection limitation
/// Now uses the consolidated camera_device channel
class CustomCameraController {
  static const MethodChannel _channel = MethodChannel('com.photobooth/camera_device');
  
  bool _isInitialized = false;
  bool _isPreviewRunning = false;
  String? _currentDeviceId;
  int? _textureId;
  
  bool get isInitialized => _isInitialized;
  bool get isPreviewRunning => _isPreviewRunning;
  String? get currentDeviceId => _currentDeviceId;
  int? get textureId => _textureId;
  
  /// Initializes camera with specific device ID
  /// This allows selecting external cameras even when they share the same lensDirection
  /// Supports both iOS and Android
  Future<void> initialize(String deviceId) async {
    if (kIsWeb) {
      throw UnsupportedError('Custom camera controller not supported on web');
    }
    
    if (!_isIOS && !_isAndroid) {
      throw UnsupportedError('Custom camera controller only supports iOS and Android');
    }
    
    try {
      AppLogger.debug('🎥 CustomCameraController: Initializing camera with device ID: $deviceId');
      AppLogger.debug('   Platform: ${_isIOS ? "iOS" : "Android"}');
      
      final result = await _channel.invokeMethod('initializeCamera', {
        'deviceId': deviceId,
      });
      
      if (result is Map && result['success'] == true) {
        _isInitialized = true;
        _currentDeviceId = deviceId;
        _textureId = result['textureId'] as int?;
        final localizedName = result['localizedName'] ?? 'Camera';
        AppLogger.debug('✅ CustomCameraController initialized: $localizedName');
        if (_textureId != null) {
          AppLogger.debug('   Texture ID: $_textureId');
        }
      } else {
        throw Exception('Failed to initialize camera: $result');
      }
    } catch (e) {
      AppLogger.debug('❌ Error initializing custom camera: $e');
      _isInitialized = false;
      rethrow;
    }
  }
  
  /// Starts camera preview
  Future<void> startPreview() async {
    if (!_isInitialized) {
      throw StateError('Camera not initialized. Call initialize() first.');
    }
    
    try {
      final result = await _channel.invokeMethod('startPreview');
      if (result is Map && result['success'] == true) {
        _isPreviewRunning = true;
        AppLogger.debug('✅ Camera preview started');
      }
    } catch (e) {
      AppLogger.debug('❌ Error starting preview: $e');
      rethrow;
    }
  }
  
  /// Stops camera preview
  Future<void> stopPreview() async {
    if (!_isInitialized) {
      return;
    }
    
    try {
      final result = await _channel.invokeMethod('stopPreview');
      if (result is Map && result['success'] == true) {
        _isPreviewRunning = false;
        AppLogger.debug('✅ Camera preview stopped');
      }
    } catch (e) {
      AppLogger.debug('❌ Error stopping preview: $e');
    }
  }
  
  /// Takes a picture and returns the file path
  Future<String> takePicture() async {
    AppLogger.debug('📸 CustomCameraController.takePicture() called');
    AppLogger.debug('   _isInitialized: $_isInitialized');
    AppLogger.debug('   _isPreviewRunning: $_isPreviewRunning');
    AppLogger.debug('   _currentDeviceId: $_currentDeviceId');
    AppLogger.debug('   _textureId: $_textureId');
    
    if (!_isInitialized) {
      final error = 'Camera not initialized. Call initialize() first.';
      AppLogger.debug('❌ $error');
      throw StateError(error);
    }
    
    if (!_isPreviewRunning) {
      final error = 'Preview not running. Call startPreview() first.';
      AppLogger.debug('❌ $error');
      throw StateError(error);
    }
    
    try {
      AppLogger.debug('📸 Invoking native takePicture method...');
      ErrorReportingManager.log('📸 Native takePicture invoked');
      
      // Set custom keys for debugging
      await ErrorReportingManager.setCustomKeys({
        'native_takePicture_deviceId': _currentDeviceId ?? 'none',
        'native_takePicture_textureId': _textureId,
        'native_takePicture_isInitialized': _isInitialized,
        'native_takePicture_isPreviewRunning': _isPreviewRunning,
      });
      
      // Add timeout to prevent infinite hang
      final result = await _channel.invokeMethod('takePicture').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.debug('❌ takePicture timed out after 10 seconds');
          ErrorReportingManager.log('⏱️ TIMEOUT: Native takePicture timed out after 10 seconds');
          
          // Record timeout to error reporting
          ErrorReportingManager.recordError(
            TimeoutException('Photo capture timed out after 10 seconds'),
            StackTrace.current,
            reason: 'Flutter-level timeout waiting for native takePicture',
            extraInfo: {
              'device_id': _currentDeviceId ?? 'unknown',
              'texture_id': _textureId,
              'is_initialized': _isInitialized,
              'is_preview_running': _isPreviewRunning,
              'platform': defaultTargetPlatform.name,
            },
          );
          
          throw TimeoutException('Photo capture timed out after 10 seconds. The camera may not be responding.');
        },
      );
      
      AppLogger.debug('📸 Native method returned: $result');
      ErrorReportingManager.log('✅ Native takePicture returned result');
      
      if (result is Map && result['success'] == true) {
        final path = result['path'] as String;
        AppLogger.debug('✅ Picture captured successfully: $path');
        ErrorReportingManager.log('✅ Photo captured successfully at: $path');
        return path;
      } else {
        final errorMsg = 'Failed to capture picture. Native result: $result';
        AppLogger.debug('❌ $errorMsg');
        ErrorReportingManager.log('❌ Native takePicture returned failure: $result');
        
        // Record to error reporting
        await ErrorReportingManager.recordError(
          Exception(errorMsg),
          StackTrace.current,
          reason: 'Native takePicture returned failure',
          extraInfo: {
            'result': result.toString(),
            'device_id': _currentDeviceId ?? 'unknown',
          },
        );
        
        throw Exception(errorMsg);
      }
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error taking picture: $e');
      AppLogger.debug('Stack trace: $stackTrace');
      
      // Log to error reporting (only if not already a timeout we logged)
      if (e is! TimeoutException) {
        ErrorReportingManager.log('❌ Error in native takePicture: $e');
        await ErrorReportingManager.recordError(
          e,
          stackTrace,
          reason: 'Exception in CustomCameraController.takePicture',
          extraInfo: {
            'error': e.toString(),
            'device_id': _currentDeviceId ?? 'unknown',
            'platform': defaultTargetPlatform.name,
          },
        );
      }
      
      rethrow;
    }
  }
  
  /// Disposes the camera controller
  Future<void> dispose() async {
    if (!_isInitialized) {
      return;
    }
    
    try {
      await stopPreview();
      await _channel.invokeMethod('disposeCamera');
      _isInitialized = false;
      _isPreviewRunning = false;
      _currentDeviceId = null;
      _textureId = null;
      AppLogger.debug('✅ CustomCameraController disposed');
    } catch (e) {
      AppLogger.debug('❌ Error disposing camera: $e');
    }
  }
}

