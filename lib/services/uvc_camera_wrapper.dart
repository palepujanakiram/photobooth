import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

/// Wrapper for UVC (USB Video Class) camera support
/// Handles initialization, preview, and capture for external USB cameras
class UvcCameraWrapper {
  UVCCameraController? _controller;
  bool _isInitialized = false;
  bool _isPreviewRunning = false;
  String? _currentDeviceId; // Format: usb_vendorId_productId

  bool get isInitialized => _isInitialized;
  bool get isPreviewRunning => _isPreviewRunning;
  String? get currentDeviceId => _currentDeviceId;
  UVCCameraController? get controller => _controller;

  /// Initialize UVC camera with USB device ID
  /// deviceId format: "usb_vendorId_productId" (e.g., "usb_1008_1888")
  Future<void> initialize(String deviceId) async {
    try {
      AppLogger.debug('🔌 UvcCameraWrapper: Initializing UVC camera with device ID: $deviceId');
      
      // Extract vendor and product IDs from deviceId
      if (!deviceId.startsWith('usb_')) {
        throw Exception('Invalid USB device ID format. Expected format: usb_vendorId_productId');
      }
      
      final parts = deviceId.substring(4).split('_'); // Remove 'usb_' prefix
      if (parts.length != 2) {
        throw Exception('Invalid USB device ID format. Expected format: usb_vendorId_productId');
      }
      
      final vendorId = int.tryParse(parts[0]);
      final productId = int.tryParse(parts[1]);
      
      if (vendorId == null || productId == null) {
        throw Exception('Invalid vendor or product ID in device ID: $deviceId');
      }
      
      AppLogger.debug('   Vendor ID: $vendorId, Product ID: $productId');
      
      // Request standard runtime permissions first (CAMERA, STORAGE, MICROPHONE)
      // The plugin checks for these permissions and will fail with "Permission denied" if they're not granted
      AppLogger.debug('   🔐 Requesting standard runtime permissions (CAMERA, STORAGE, MICROPHONE)...');
      final cameraStatus = await Permission.camera.request();
      
      // Request storage permission - the plugin checks for this in its native code
      // On Android 13+, READ_EXTERNAL_STORAGE is not needed for camera preview,
      // but the plugin might still check for it, so we request it anyway
      PermissionStatus storageStatus = await Permission.storage.request();
      
      // Also try photos permission for Android 13+ as a fallback
      if (Platform.isAndroid && storageStatus.isDenied) {
        try {
          final photosStatus = await Permission.photos.request();
          AppLogger.debug('   📱 Also requested photos permission: $photosStatus');
          // If photos is granted, consider it as storage permission granted
          if (photosStatus.isGranted) {
            storageStatus = photosStatus;
          }
        } catch (e) {
          AppLogger.debug('   📱 Photos permission not available: $e');
        }
      }
      
      // Request microphone permission for webcam audio support
      final microphoneStatus = await Permission.microphone.request();
      AppLogger.debug('   🎤 Microphone permission: $microphoneStatus');
      
      if (cameraStatus.isGranted) {
        AppLogger.debug('   ✅ Camera permission granted');
        if (storageStatus.isGranted) {
          AppLogger.debug('   ✅ Storage/Photos permission granted');
          if (microphoneStatus.isGranted) {
            AppLogger.debug('   ✅ Microphone permission granted');
          } else {
            AppLogger.debug('   ⚠️ Microphone permission denied: $microphoneStatus (non-critical for camera preview)');
            // Microphone permission is not critical for camera preview, so we continue
          }
        } else {
          AppLogger.debug('   ❌ Storage/Photos permission denied: $storageStatus');
          AppLogger.debug('   ❌ ERROR: The plugin requires storage permission and will fail without it');
          AppLogger.debug('   💡 Please grant storage permission using the Settings button (⚙️) in the top right corner');
          AppLogger.debug('   💡 Or go to: Settings → Apps → Photo Booth → Permissions → Storage');
          // Throw error to prevent initialization - plugin will fail anyway
          throw Exception('Storage permission is required for the external camera. Please tap the Settings button (⚙️) in the top right corner to grant storage permission.');
        }
      } else {
        AppLogger.debug('   ❌ Camera permission denied: $cameraStatus');
        throw Exception('Camera permission denied - required for UVC camera');
      }
      
      // Request USB permission explicitly before the plugin tries to access the device
      // This ensures permission is granted before the plugin attempts to open the camera
      // The plugin may not request permission automatically, so we do it here
      AppLogger.debug('   🔐 Requesting USB permission explicitly...');
      AppLogger.debug('   ⏳ Waiting for user to grant USB permission...');
      
      final usbPermissionGranted = await _requestUsbPermission(vendorId, productId);
      
      if (!usbPermissionGranted) {
        AppLogger.debug('   ❌ USB permission not granted');
        AppLogger.debug('   ❌ ERROR: USB permission is required for the external camera');
        AppLogger.debug('   💡 The USB permission dialog may have been dismissed or denied');
        AppLogger.debug('   💡 To fix this:');
        AppLogger.debug('      1. Select the external camera again');
        AppLogger.debug('      2. When the permission dialog appears, tap "OK" or "Allow"');
        AppLogger.debug('      3. ⚠️ IMPORTANT: Do not dismiss the dialog - you must explicitly grant permission');
        AppLogger.debug('      4. If the dialog does not appear, try unplugging and replugging the USB camera');
        AppLogger.debug('      5. Or go to: Settings → Apps → Photo Booth → Permissions → USB');
        // Throw error to prevent initialization - plugin will fail anyway without USB permission
        throw Exception('USB permission is required for the external camera. Please select the external camera again and tap "OK" or "Allow" when the permission dialog appears. Do not dismiss the dialog - you must explicitly grant permission.');
      }
      
      // USB permission has been granted - now we can proceed with USB-related operations
      AppLogger.debug('   ✅ USB permission granted by user');
      AppLogger.debug('   ⏳ Waiting for permission to fully propagate...');
      // Wait a moment to ensure permission is fully propagated to the system
      await Future.delayed(const Duration(milliseconds: 500));
      AppLogger.debug('   ✅ Permission propagation complete');
      
      // Now that USB permission is confirmed, we can create the controller and initialize USB camera
      AppLogger.debug('   🚀 Creating UVC camera controller (USB permission confirmed)...');
      _controller = UVCCameraController();
      _currentDeviceId = deviceId;
      
      // Store vendor/product IDs for reference (may be used for device selection)
      _vendorId = vendorId;
      _productId = productId;
      AppLogger.debug('   ✅ Stored vendor/product IDs for device selection');
      
      AppLogger.debug('✅ UvcCameraWrapper initialized successfully (USB permission granted)');
      _isInitialized = true;
    } catch (e) {
      AppLogger.debug('❌ Error initializing UVC camera: $e');
      _isInitialized = false;
      _controller = null;
      _currentDeviceId = null;
      rethrow;
    }
  }
  
  int? _vendorId;
  int? _productId;
  
  // Platform channel for USB permission requests
  // Note: This must match CAMERA_CONTROL_CHANNEL in MainActivity.kt
  static const MethodChannel _platform = MethodChannel('com.photobooth/camera_device');
  
  /// Request USB permission for the device
  /// This method waits for the user to respond to the USB permission dialog
  /// Returns true if permission is granted, false otherwise
  /// IMPORTANT: This method will block until the user responds to the permission dialog
  Future<bool> _requestUsbPermission(int vendorId, int productId) async {
    try {
      AppLogger.debug('   📱 Requesting USB permission via platform channel...');
      AppLogger.debug('   💡 A USB permission dialog will appear - please grant permission');
      AppLogger.debug('   ⏳ Waiting for user response...');
      
      // This call will show the USB permission dialog and wait for user response
      // The platform channel will not return until the user responds (via BroadcastReceiver)
      final result = await _platform.invokeMethod(
        'requestUsbPermission',
        {'vendorId': vendorId, 'productId': productId},
      );
      
      AppLogger.debug('   📨 Received response from platform channel');
      
      // Handle the result - it might be a Map or other type
      if (result != null) {
        // Try to cast to Map, handling different possible types
        final Map<dynamic, dynamic>? resultMap = result is Map ? result : null;
        if (resultMap != null && resultMap['granted'] == true) {
          AppLogger.debug('   ✅ USB permission granted by user');
          return true;
        } else {
          AppLogger.debug('   ❌ USB permission denied or not granted by user');
          AppLogger.debug('   📋 Result: $result');
          return false;
        }
      } else {
        AppLogger.debug('   ❌ USB permission request returned null');
        AppLogger.debug('   💡 This may indicate the permission dialog was dismissed');
        return false;
      }
    } on PlatformException catch (e) {
      AppLogger.debug('   ❌ Error requesting USB permission: ${e.code}, ${e.message}');
      if (e.code == 'USB_DEVICE_NOT_FOUND') {
        AppLogger.debug('   💡 USB device not found - please ensure the camera is connected');
        AppLogger.debug('   💡 Try unplugging and replugging the USB camera');
      } else if (e.code == 'USB_PERMISSION_DISMISSED') {
        AppLogger.debug('   💡 USB permission dialog was dismissed (not denied)');
        AppLogger.debug('   💡 The permission dialog was closed without selecting "Allow" or "Deny"');
        AppLogger.debug('   💡 This happens when you press back button or tap outside the dialog');
        AppLogger.debug('   💡 Please select the external camera again and tap "OK" or "Allow" when the dialog appears');
        AppLogger.debug('   ⚠️ IMPORTANT: Do not dismiss the dialog - you must explicitly grant permission');
      } else if (e.code == 'USB_PERMISSION_DENIED') {
        AppLogger.debug('   💡 USB permission was denied by user');
        AppLogger.debug('   💡 Please unplug and replug the USB camera, then grant permission when dialog appears');
      }
      return false;
    } catch (e) {
      AppLogger.debug('   ❌ Unexpected error requesting USB permission: $e');
      AppLogger.debug('   📋 Error type: ${e.runtimeType}');
      return false;
    }
  }

  /// Create the UVC camera view widget
  /// This must be called after initialize() and USB permission is granted
  /// The view will automatically initialize the camera when created
  /// IMPORTANT: USB permission must be granted before calling this method
  Widget createView({double? width, double? height}) {
    if (_controller == null) {
      throw StateError('UVC camera not initialized. Call initialize() first.');
    }
    
    if (!_isInitialized) {
      throw StateError('UVC camera initialization not complete. USB permission may not be granted.');
    }
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = width ?? constraints.maxWidth;
        final viewHeight = height ?? constraints.maxHeight;
        
        // Create the view - USB permission has already been granted in initialize()
        // The plugin should auto-detect the camera based on available USB devices
        // Since USB permission is already granted, the plugin should be able to access the device
        AppLogger.debug('   📱 Creating UVCCameraView widget (USB permission already granted)...');
        AppLogger.debug('   📏 View size: ${viewWidth.toInt()}x${viewHeight.toInt()}');
        AppLogger.debug('   💡 Plugin will auto-detect USB camera device');
        AppLogger.debug('   💡 Expected device: vendor=$_vendorId, product=$_productId');
        AppLogger.debug('   ✅ USB permission is already granted - plugin can access device');
        
        // The plugin will auto-detect the USB device
        // We pass null for params to let the plugin handle device detection
        // The plugin should find the device matching the vendor/product IDs
        // Since permission is already granted, the plugin should be able to open the device
        final view = UVCCameraView(
          cameraController: _controller!,
          width: viewWidth,
          height: viewHeight,
          params: null, // Plugin will auto-detect - permission is already granted
          autoDispose: false,
        );
        
        AppLogger.debug('   ✅ UVCCameraView widget created (USB permission confirmed)');
        
        // Check camera state after view is created and opened
        // USB permission is already granted, so the plugin should be able to open the device
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Check state multiple times to monitor camera opening progress
          // Since USB permission is already granted, the plugin should be able to access the device
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_controller != null) {
              final state = _controller!.getCameraState;
              AppLogger.debug('   📊 UVC camera state (500ms): $state');
            }
          });
          
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_controller != null) {
              final state = _controller!.getCameraState;
              AppLogger.debug('   📊 UVC camera state (1.5s): $state');
              
              if (state == UVCCameraState.opened) {
                _isPreviewRunning = true;
                AppLogger.debug('✅ UVC camera preview is running');
              } else if (state == UVCCameraState.error) {
                AppLogger.debug('   ❌ UVC camera error state');
                AppLogger.debug('   💡 USB permission is granted, but camera may have other issues');
                AppLogger.debug('   💡 Troubleshooting steps:');
                AppLogger.debug('      1. Ensure USB device is connected');
                AppLogger.debug('      2. Try unplugging and replugging the USB device');
                AppLogger.debug('      3. Check if device is compatible with UVC');
                AppLogger.debug('      4. Verify device is not being used by another app');
                AppLogger.debug('   💡 Expected device: vendor=$_vendorId, product=$_productId');
                // Try to check again after a longer delay in case device needs more time
                Future.delayed(const Duration(milliseconds: 5000), () {
                  if (_controller != null) {
                    final newState = _controller!.getCameraState;
                    AppLogger.debug('   📊 UVC camera state (6.5s): $newState');
                    if (newState == UVCCameraState.opened) {
                      _isPreviewRunning = true;
                      AppLogger.debug('✅ UVC camera preview started (delayed)');
                    } else if (newState == UVCCameraState.error) {
                      AppLogger.debug('   ❌ UVC camera still in error state');
                      AppLogger.debug('   💡 The plugin may not be able to access the USB device');
                      AppLogger.debug('   💡 Please check:');
                      AppLogger.debug('      - USB device is connected');
                      AppLogger.debug('      - USB permission was granted (should be granted)');
                      AppLogger.debug('      - Device is compatible with UVC');
                      AppLogger.debug('      - Device is not being used by another application');
                    }
                  }
                });
              } else {
                AppLogger.debug('   ⚠️ UVC camera not opened yet, state: $state');
                // Try to check again after a longer delay
                Future.delayed(const Duration(milliseconds: 3000), () {
                  if (_controller != null) {
                    final delayedState = _controller!.getCameraState;
                    AppLogger.debug('   📊 UVC camera state (4.5s): $delayedState');
                    if (delayedState == UVCCameraState.opened) {
                      _isPreviewRunning = true;
                      AppLogger.debug('✅ UVC camera preview started (delayed)');
                    }
                  }
                });
              }
            }
          });
        });
        
        return view;
      },
    );
  }

  /// Start camera preview (camera is initialized when view is created)
  Future<void> startPreview() async {
    if (!_isInitialized || _controller == null) {
      throw StateError('UVC camera not initialized. Call initialize() first.');
    }
    
    try {
      AppLogger.debug('🎬 Starting UVC camera preview...');
      // The camera is initialized when the view is created
      // Check if camera state is open
      if (_controller!.getCameraState == UVCCameraState.opened) {
        _isPreviewRunning = true;
        AppLogger.debug('✅ UVC camera preview is running');
      } else {
        AppLogger.debug('   Camera state: ${_controller!.getCameraState}');
        // Wait a bit for camera to initialize
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller!.getCameraState == UVCCameraState.opened) {
          _isPreviewRunning = true;
          AppLogger.debug('✅ UVC camera preview started');
        } else {
          throw StateError('UVC camera not opened. State: ${_controller!.getCameraState}');
        }
      }
    } catch (e) {
      AppLogger.debug('❌ Error starting UVC preview: $e');
      _isPreviewRunning = false;
      rethrow;
    }
  }

  /// Stop camera preview
  Future<void> stopPreview() async {
    if (!_isPreviewRunning || _controller == null) {
      return;
    }
    
    try {
      AppLogger.debug('⏹️ Stopping UVC camera preview...');
      _isPreviewRunning = false;
      AppLogger.debug('✅ UVC camera preview stopped');
    } catch (e) {
      AppLogger.debug('❌ Error stopping UVC preview: $e');
    }
  }

  /// Take a picture
  Future<String> takePicture() async {
    if (!_isInitialized || _controller == null) {
      throw StateError('UVC camera not initialized. Call initialize() first.');
    }
    
    if (_controller!.getCameraState != UVCCameraState.opened) {
      throw StateError('UVC camera not opened. State: ${_controller!.getCameraState}');
    }
    
    try {
      AppLogger.debug('📸 Taking picture with UVC camera...');
      await _controller!.takePicture();
      // Wait for the picture to be captured
      await Future.delayed(const Duration(milliseconds: 500));
      final imagePath = _controller!.getTakePicturePath;
      if (imagePath.isEmpty) {
        throw Exception('Picture path is empty');
      }
      AppLogger.debug('✅ Picture captured: $imagePath');
      return imagePath;
    } catch (e) {
      AppLogger.debug('❌ Error taking picture: $e');
      rethrow;
    }
  }

  /// Close the camera
  Future<void> closeCamera() async {
    try {
      await stopPreview();
      if (_controller != null) {
        _controller!.closeCamera();
        AppLogger.debug('✅ UVC camera closed');
      }
    } catch (e) {
      AppLogger.debug('❌ Error closing UVC camera: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await closeCamera();
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _isPreviewRunning = false;
      _currentDeviceId = null;
      AppLogger.debug('✅ UvcCameraWrapper disposed');
    } catch (e) {
      AppLogger.debug('❌ Error disposing UVC camera wrapper: $e');
    }
  }
}
