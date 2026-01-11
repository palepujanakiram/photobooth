import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../utils/logger.dart';
import '../utils/exceptions.dart' as app_exceptions;

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
        // Check for permission errors
        if (result is Map) {
          final errorCode = result['code'] as String?;
          if (errorCode == 'PERMISSION_DENIED' || errorCode == 'PERMISSION_ERROR') {
            final errorMessage = result['message'] as String? ?? 'Camera permission denied';
            AppLogger.debug('❌ Permission error: $errorMessage');
            throw app_exceptions.PermissionException(errorMessage);
          }
        }
        throw Exception('Failed to initialize camera: $result');
      }
    } on app_exceptions.PermissionException {
      rethrow;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Platform error initializing custom camera: ${e.code} - ${e.message}');
      // Check if it's a permission error
      if (e.code == 'PERMISSION_DENIED' || e.code == 'PERMISSION_ERROR') {
        throw app_exceptions.PermissionException(e.message ?? 'Camera permission denied');
      }
      _isInitialized = false;
      rethrow;
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
    if (!_isInitialized) {
      throw StateError('Camera not initialized. Call initialize() first.');
    }
    
    if (!_isPreviewRunning) {
      throw StateError('Preview not running. Call startPreview() first.');
    }
    
    try {
      AppLogger.debug('📸 Taking picture...');
      final result = await _channel.invokeMethod('takePicture');
      
      if (result is Map && result['success'] == true) {
        final path = result['path'] as String;
        AppLogger.debug('✅ Picture captured: $path');
        return path;
      } else {
        throw Exception('Failed to capture picture: $result');
      }
    } catch (e) {
      AppLogger.debug('❌ Error taking picture: $e');
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

