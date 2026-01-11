import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../utils/logger.dart';
import '../../services/android_uvc_camera_helper.dart';
import '../../services/android_camera_device_helper.dart';

enum PermissionType {
  camera,
  photos,
  storage,
}

class PermissionItem {
  final PermissionType type;
  final String title;
  final String description;
  final ph.Permission permission;
  final bool isRequired;

  PermissionItem({
    required this.type,
    required this.title,
    required this.description,
    required this.permission,
    this.isRequired = true,
  });
}

class PermissionsViewModel extends ChangeNotifier {
  final List<PermissionItem> _permissions = [];
  final Map<PermissionType, ph.PermissionStatus> _permissionStatuses = {};
  List<UvcCameraInfo> _connectedUvcCameras = [];
  bool _isCheckingUvcCameras = false;

  List<PermissionItem> get permissions => _permissions;
  List<UvcCameraInfo> get connectedUvcCameras => _connectedUvcCameras;
  bool get isCheckingUvcCameras => _isCheckingUvcCameras;
  
  bool get allRequiredPermissionsGranted {
    return _permissions.where((p) => p.isRequired).every((p) {
      final status = _permissionStatuses[p.type];
      // If permission status is null, it hasn't been checked yet - don't block continue
      if (status == null) return true;
      return status == ph.PermissionStatus.granted || status == ph.PermissionStatus.limited;
    });
  }

  PermissionsViewModel() {
    _initializePermissions().then((_) {
      _checkAllPermissions();
      if (Platform.isAndroid) {
        _checkConnectedUvcCameras();
      }
    });
  }

  Future<void> _initializePermissions() async {
    _permissions.addAll([
      PermissionItem(
        type: PermissionType.camera,
        title: 'Camera',
        description: 'Required to capture photos using your device camera or external USB cameras.',
        permission: ph.Permission.camera,
        isRequired: true,
      ),
    ]);

    // Handle Photos/Storage permissions
    // On Android 13+ (API 33+), use photos permission
    // On older Android versions, use storage permission
    if (Platform.isAndroid) {
      // Check if photos permission is available (Android 13+)
      // If not, use storage permission (Android < 13)
      try {
        await ph.Permission.photos.status; // Check if photos permission is available
        // If we can check status, photos permission is available
        _permissions.add(
          PermissionItem(
            type: PermissionType.photos,
            title: 'Photos',
            description: 'Required to save and access photos from your device gallery.',
            permission: ph.Permission.photos,
            isRequired: true,
          ),
        );
      } catch (e) {
        // Photos permission not available, use storage instead
        AppLogger.debug('Photos permission not available, using storage permission: $e');
        _permissions.add(
          PermissionItem(
            type: PermissionType.photos,
            title: 'Photos',
            description: 'Required to save and access photos from your device gallery.',
            permission: ph.Permission.storage,
            isRequired: true,
          ),
        );
      }
    } else {
      // iOS - use photos permission
      _permissions.add(
        PermissionItem(
          type: PermissionType.photos,
          title: 'Photos',
          description: 'Required to save and access photos from your device gallery.',
          permission: ph.Permission.photos,
          isRequired: true,
        ),
      );
    }
  }

  Future<void> _checkAllPermissions() async {
    for (final permissionItem in _permissions) {
      await _checkPermission(permissionItem);
    }
    notifyListeners();
  }

  Future<void> _checkPermission(PermissionItem permissionItem) async {
    try {
      final status = await permissionItem.permission.status;
      _permissionStatuses[permissionItem.type] = status;
    } catch (e) {
      AppLogger.debug('Error checking permission ${permissionItem.type}: $e');
      _permissionStatuses[permissionItem.type] = ph.PermissionStatus.denied;
    }
  }

  ph.PermissionStatus? getPermissionStatus(PermissionType type) {
    return _permissionStatuses[type];
  }

  bool isPermissionGranted(PermissionType type) {
    final status = _permissionStatuses[type];
    return status == ph.PermissionStatus.granted || status == ph.PermissionStatus.limited;
  }

  bool isPermissionPermanentlyDenied(PermissionType type) {
    final status = _permissionStatuses[type];
    return status == ph.PermissionStatus.permanentlyDenied;
  }

  Future<bool> requestPermission(PermissionItem permissionItem) async {
    try {
      AppLogger.debug('Requesting permission: ${permissionItem.type}');
      
      // Check current status first
      final currentStatus = await permissionItem.permission.status;
      AppLogger.debug('Current permission status: $currentStatus');
      
      // If already granted, we're done
      if (currentStatus.isGranted || currentStatus.isLimited) {
        _permissionStatuses[permissionItem.type] = currentStatus;
        notifyListeners();
        return true;
      }
      
      // If permanently denied, open settings
      if (currentStatus.isPermanentlyDenied) {
        AppLogger.debug('Permission ${permissionItem.type} is permanently denied, opening settings');
        await ph.openAppSettings();
        _permissionStatuses[permissionItem.type] = currentStatus;
        notifyListeners();
        return false;
      }
      
      // For photos permission on Android, try photos first, then storage as fallback
      if (permissionItem.type == PermissionType.photos && Platform.isAndroid) {
        // First try photos permission (Android 13+)
        try {
          final photosStatus = await ph.Permission.photos.request();
          AppLogger.debug('Photos permission request result: $photosStatus');
          
          // If photos permission is granted or limited, we're done
          if (photosStatus.isGranted || photosStatus.isLimited) {
            _permissionStatuses[PermissionType.photos] = photosStatus;
            notifyListeners();
            return true;
          }
          
          // If photos permission is permanently denied, open settings
          if (photosStatus.isPermanentlyDenied) {
            AppLogger.debug('Photos permission permanently denied, opening settings');
            await ph.openAppSettings();
            _permissionStatuses[PermissionType.photos] = photosStatus;
            notifyListeners();
            return false;
          }
          
          // If photos permission is denied after request, it might mean:
          // 1. User denied it (on Android 13+, this might not show dialog again)
          // 2. Permission is not available on this Android version
          // Try storage as fallback, but if that also fails, open settings
          if (photosStatus == ph.PermissionStatus.denied) {
            AppLogger.debug('Photos permission denied after request. Trying storage as fallback.');
          }
        } catch (e) {
          AppLogger.debug('Error requesting photos permission, trying storage: $e');
        }
        
        // Try storage permission as fallback (Android < 13)
        // Only try if photos permission is not available or failed
        try {
          final storageStatus = await ph.Permission.storage.request();
          AppLogger.debug('Storage permission request result: $storageStatus');
          _permissionStatuses[PermissionType.photos] = storageStatus;
          notifyListeners();
          
          // If storage is also denied or permanently denied, open settings
          if (storageStatus.isPermanentlyDenied || 
              (storageStatus == ph.PermissionStatus.denied && currentStatus == ph.PermissionStatus.denied)) {
            AppLogger.debug('Storage permission also denied. Opening settings.');
            await ph.openAppSettings();
          }
          
          return storageStatus.isGranted || storageStatus.isLimited;
        } catch (e) {
          AppLogger.debug('Error requesting storage permission: $e');
          // If both fail, open settings
          await ph.openAppSettings();
          return false;
        }
      }
      
      // For other permissions, request normally
      final status = await permissionItem.permission.request();
      _permissionStatuses[permissionItem.type] = status;
      notifyListeners();
      
      if (status.isPermanentlyDenied) {
        AppLogger.debug('Permission ${permissionItem.type} is permanently denied');
        await ph.openAppSettings();
      }
      
      return status.isGranted || status.isLimited;
    } catch (e) {
      AppLogger.debug('Error requesting permission ${permissionItem.type}: $e');
      // On error, try opening settings as last resort
      try {
        await ph.openAppSettings();
      } catch (settingsError) {
        AppLogger.debug('Error opening app settings: $settingsError');
      }
      return false;
    }
  }

  Future<void> openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      AppLogger.debug('Error opening app settings: $e');
    }
  }

  Future<void> refreshPermissions() async {
    await _checkAllPermissions();
    if (Platform.isAndroid) {
      await _checkConnectedUvcCameras();
    }
  }

  Future<void> _checkConnectedUvcCameras() async {
    if (!Platform.isAndroid) return;
    
    _isCheckingUvcCameras = true;
    notifyListeners();
    
    try {
      final cameras = await AndroidUvcCameraHelper.getUvcCameras();
      _connectedUvcCameras = cameras ?? [];
      AppLogger.debug('Found ${_connectedUvcCameras.length} connected UVC camera(s)');
    } catch (e) {
      AppLogger.debug('Error checking UVC cameras: $e');
      _connectedUvcCameras = [];
    } finally {
      _isCheckingUvcCameras = false;
      notifyListeners();
    }
  }

  Future<bool> requestUsbPermission(UvcCameraInfo camera) async {
    if (!Platform.isAndroid) return false;
    
    try {
      AppLogger.debug('Requesting USB permission for camera: ${camera.productName}');
      // Request permission proactively using the dedicated method
      final result = await AndroidCameraDeviceHelper.requestUsbPermission(
        camera.vendorId,
        camera.productId,
      );
      
      if (result != null && result['success'] == true) {
        // Permission granted, refresh camera list to update permission status
        await _checkConnectedUvcCameras();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.debug('Error requesting USB permission: $e');
      return false;
    }
  }
}
