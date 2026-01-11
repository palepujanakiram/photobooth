import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'permissions_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';
import '../../services/android_uvc_camera_helper.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  late PermissionsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = PermissionsViewModel();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh permissions when app comes back to foreground (e.g., from settings)
    if (state == AppLifecycleState.resumed) {
      _viewModel.refreshPermissions();
    }
  }

  Future<void> _handlePermissionRequest(PermissionItem permissionItem) async {
    final status = _viewModel.getPermissionStatus(permissionItem.type);
    
    if (status == PermissionStatus.granted || status == PermissionStatus.limited) {
      // Permission already granted, open app settings
      await _viewModel.openAppSettings();
    } else if (status == PermissionStatus.permanentlyDenied) {
      // Permission permanently denied, open app settings
      await _viewModel.openAppSettings();
    } else {
      // Request permission
      await _viewModel.requestPermission(permissionItem);
    }
  }

  void _handleContinue() {
    Navigator.pushNamed(context, AppConstants.kRouteCapture);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<PermissionsViewModel>(
        builder: (context, viewModel, child) {
          return CupertinoPageScaffold(
            navigationBar: AppTopBar(
              title: 'Permissions',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Text(
                            'The app needs the following permissions to function properly:',
                            style: TextStyle(
                              fontSize: 16,
                              color: CupertinoColors.secondaryLabel,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ...viewModel.permissions.map((permissionItem) {
                            return _PermissionCard(
                              permissionItem: permissionItem,
                              status: viewModel.getPermissionStatus(permissionItem.type),
                              isGranted: viewModel.isPermissionGranted(permissionItem.type),
                              isPermanentlyDenied: viewModel.isPermissionPermanentlyDenied(permissionItem.type),
                              onRequest: () => _handlePermissionRequest(permissionItem),
                            );
                          }),
                          const SizedBox(height: 16),
                          // USB Permission Info with connected cameras
                          Consumer<PermissionsViewModel>(
                            builder: (context, viewModel, child) {
                              return _UsbPermissionInfoCard(
                                connectedCameras: viewModel.connectedUvcCameras,
                                isChecking: viewModel.isCheckingUvcCameras,
                                onRequestPermission: (camera) async {
                                  await viewModel.requestUsbPermission(camera);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Continue button
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: const BoxDecoration(
                      color: CupertinoColors.white,
                      border: Border(
                        top: BorderSide(
                          color: CupertinoColors.separator,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: AppConstants.kButtonHeight,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: viewModel.allRequiredPermissionsGranted
                            ? _handleContinue
                            : null,
                        color: AppTheme.primaryColor,
                        disabledColor: CupertinoColors.systemGrey3,
                        borderRadius: BorderRadius.circular(12),
                        child: Text(
                          AppConstants.kContinueButtonText,
                          style: AppTheme.buttonTextStyle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final PermissionItem permissionItem;
  final PermissionStatus? status;
  final bool isGranted;
  final bool isPermanentlyDenied;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.permissionItem,
    required this.status,
    required this.isGranted,
    required this.isPermanentlyDenied,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.separator,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  permissionItem.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              if (isGranted)
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: CupertinoColors.systemGreen,
                      size: 20,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Granted',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.systemGreen,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else if (isPermanentlyDenied)
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      color: CupertinoColors.systemOrange,
                      size: 20,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Denied',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.systemOrange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              else
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.circle,
                      color: CupertinoColors.systemGrey,
                      size: 20,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Not Granted',
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.secondaryLabel,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            permissionItem.description,
            style: const TextStyle(
              fontSize: 15,
              color: CupertinoColors.secondaryLabel,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onRequest,
              color: isGranted || isPermanentlyDenied
                  ? CupertinoColors.systemGrey
                  : AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(8),
              child: Text(
                isGranted
                    ? 'Open Settings'
                    : isPermanentlyDenied
                        ? 'Open Settings'
                        : 'Grant Permission',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsbPermissionInfoCard extends StatelessWidget {
  final List<UvcCameraInfo> connectedCameras;
  final bool isChecking;
  final Function(UvcCameraInfo) onRequestPermission;

  const _UsbPermissionInfoCard({
    required this.connectedCameras,
    required this.isChecking,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.separator,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                CupertinoIcons.info_circle_fill,
                color: CupertinoColors.systemBlue,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'USB Camera Access',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isChecking)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CupertinoActivityIndicator(radius: 8),
                ),
                SizedBox(width: 8),
                Text(
                  'Checking for connected USB cameras...',
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            )
          else if (connectedCameras.isEmpty)
            const Text(
              'No USB cameras detected. If you connect a USB camera, you will be prompted to grant USB device access when needed.',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel,
                height: 1.4,
              ),
            )
          else ...[
            Text(
              'Found ${connectedCameras.length} USB camera(s) connected. Request permission to access them:',
              style: const TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...connectedCameras.map((camera) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: CupertinoColors.separator,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            camera.productName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.label,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            camera.hasPermission ? 'Permission granted' : 'Permission needed',
                            style: TextStyle(
                              fontSize: 13,
                              color: camera.hasPermission
                                  ? CupertinoColors.systemGreen
                                  : CupertinoColors.systemOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!camera.hasPermission)
                      SizedBox(
                        height: 36,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minSize: 0,
                          onPressed: () => onRequestPermission(camera),
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                          child: const Text(
                            'Grant',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.white,
                            ),
                          ),
                        ),
                      )
                    else
                      const Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: CupertinoColors.systemGreen,
                        size: 24,
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
