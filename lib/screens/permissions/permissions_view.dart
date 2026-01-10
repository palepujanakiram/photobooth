import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import '../../views/widgets/app_colors.dart';
import '../../utils/constants.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _isRequesting = false;
  String? _errorMessage;
  bool _allPermissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final storageStatus = Platform.isAndroid
        ? await Permission.storage.status
        : await Permission.photos.status;
    final microphoneStatus = await Permission.microphone.status;

    if (cameraStatus.isGranted && storageStatus.isGranted && microphoneStatus.isGranted) {
      setState(() {
        _allPermissionsGranted = true;
      });
      // Navigate to main app after a brief delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppConstants.kRouteTakePhoto);
        }
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      // Request camera permission first
      final cameraStatus = await Permission.camera.request();
      
      // Wait for camera permission dialog to close before requesting next permission
      // This ensures dialogs don't overlap
      if (cameraStatus.isDenied || cameraStatus.isPermanentlyDenied) {
        // Wait a bit longer if permission was denied to show error
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // Wait for dialog to close if granted
        await Future.delayed(const Duration(milliseconds: 800));
      }

      // Request storage/photos permission
      if (Platform.isAndroid) {
        // On Android 13+ (API 33+), use READ_MEDIA_IMAGES (photos permission)
        // On Android 12 and below, use READ_EXTERNAL_STORAGE (storage permission)
        try {
          // Try photos permission first (for Android 13+)
          await Permission.photos.request();
          // Small delay to allow dialog to appear
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          // Photos permission not available (Android < 13)
        }
        
        // Also request storage permission (for Android 12 and below)
        // This won't show a dialog on Android 13+ but won't hurt
        await Permission.storage.request();
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        // iOS
        await Permission.photos.request();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Request microphone permission (for webcam audio)
      await Permission.microphone.request();
      await Future.delayed(const Duration(milliseconds: 300));

      // Re-check permissions after requests with a small delay
      await Future.delayed(const Duration(milliseconds: 200));
      final finalCameraStatus = await Permission.camera.status;
      final finalStorageStatus = Platform.isAndroid
          ? await Permission.storage.status
          : await Permission.photos.status;
      final finalMicrophoneStatus = await Permission.microphone.status;
      
      // Also check photos permission status on Android
      PermissionStatus? finalPhotosStatus;
      if (Platform.isAndroid) {
        try {
          finalPhotosStatus = await Permission.photos.status;
        } catch (e) {
          // Photos permission not available
        }
      }

      // Check if all permissions are granted
      // On Android 13+, photos permission is sufficient
      // On Android 12 and below, storage permission is needed
      final isStorageGranted = (finalPhotosStatus != null && finalPhotosStatus.isGranted) ||
          (finalStorageStatus.isGranted);
      
      if (finalCameraStatus.isGranted && isStorageGranted && finalMicrophoneStatus.isGranted) {
        setState(() {
          _allPermissionsGranted = true;
          _isRequesting = false;
        });
        // Wait a bit longer to ensure permissions are fully propagated
        // This helps prevent exceptions when navigating to TakePhotoScreen
        await Future.delayed(const Duration(milliseconds: 500));
        // Navigate to main app
        if (mounted) {
          try {
            Navigator.of(context).pushReplacementNamed(AppConstants.kRouteTakePhoto);
          } catch (e) {
            debugPrint('Error navigating to TakePhotoScreen: $e');
            setState(() {
              _errorMessage = 'Error navigating to camera screen. Please try again.';
            });
          }
        }
      } else {
        setState(() {
          _isRequesting = false;
          if (!finalCameraStatus.isGranted) {
            if (finalCameraStatus.isPermanentlyDenied) {
              _errorMessage = 'Camera permission is permanently denied. Please grant it in app settings.';
            } else {
              _errorMessage = 'Camera permission is required to take photos.';
            }
          } else if (!isStorageGranted) {
            final deniedStatus = (finalPhotosStatus?.isPermanentlyDenied == true) || 
                (finalStorageStatus.isPermanentlyDenied);
            if (deniedStatus) {
              _errorMessage = 'Storage permission is permanently denied. Please tap "Open Settings" to grant it.';
            } else {
              _errorMessage = 'Storage permission is required to save photos and use external cameras.';
            }
          } else if (!finalMicrophoneStatus.isGranted) {
            if (finalMicrophoneStatus.isPermanentlyDenied) {
              _errorMessage = 'Microphone permission is permanently denied. Please grant it in app settings.';
            } else {
              _errorMessage = 'Microphone permission is required for webcam audio.';
            }
          }
        });
      }
    } catch (e) {
      setState(() {
        _isRequesting = false;
        _errorMessage = 'Error requesting permissions: $e';
      });
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    return CupertinoPageScaffold(
      backgroundColor: appColors.backgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Icon(
                CupertinoIcons.lock_shield,
                size: 80,
                color: appColors.primaryColor,
              ),
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Permissions Required',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: appColors.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'Photo Booth needs the following permissions to work properly:',
                style: TextStyle(
                  fontSize: 16,
                  color: appColors.textColor.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // Permission list
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildPermissionItem(
                        context,
                        CupertinoIcons.camera,
                        'Camera',
                        'Required to take photos with built-in and external cameras',
                        appColors,
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionItem(
                        context,
                        CupertinoIcons.folder,
                        Platform.isAndroid 
                          ? 'Storage / Photos' 
                          : 'Photos',
                        Platform.isAndroid
                          ? 'Required to save photos and access external USB cameras (Android 13+: Photos, Android 12-: Storage)'
                          : 'Required to save photos and access external cameras',
                        appColors,
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionItem(
                        context,
                        CupertinoIcons.mic,
                        'Microphone',
                        'Required for webcam audio support (optional for camera-only use)',
                        appColors,
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionItem(
                        context,
                        CupertinoIcons.link,
                        'USB Access',
                        'Required for external USB cameras (permission requested when camera is connected)',
                        appColors,
                      ),
                      const SizedBox(height: 24),
                      // Note about USB permissions
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: appColors.surfaceColor.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.info,
                              size: 20,
                              color: appColors.primaryColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'USB permission is required for external cameras and will be requested when you connect a USB camera.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: appColors.textColor.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 14,
                      color: appColors.errorColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              // Request button
              if (!_allPermissionsGranted)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: CupertinoButton(
                    onPressed: _isRequesting ? null : _requestPermissions,
                    color: appColors.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    child: _isRequesting
                        ? CupertinoActivityIndicator(
                            color: appColors.buttonTextColor,
                          )
                        : Text(
                            'Grant Permissions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: appColors.buttonTextColor,
                            ),
                          ),
                  ),
                ),
              
              // Open settings button (if permissions denied)
              if (_errorMessage != null && !_allPermissionsGranted)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: CupertinoButton(
                      onPressed: _openSettings,
                      color: CupertinoColors.systemGrey,
                      borderRadius: BorderRadius.circular(12),
                      child: Text(
                        'Open Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: appColors.buttonTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    AppColors appColors, {
    bool isOptional = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 32,
          color: appColors.primaryColor,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: appColors.textColor,
                    ),
                  ),
                  if (isOptional) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: appColors.primaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Optional',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: appColors.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: appColors.textColor.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
