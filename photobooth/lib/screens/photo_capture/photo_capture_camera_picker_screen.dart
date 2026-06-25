import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:uvccamera/uvccamera.dart';

import '../../services/error_reporting/error_reporting_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';
import 'photo_capture_camera_selection_helpers.dart';
import 'photo_capture_viewmodel.dart';

/// Camera list with force-refresh on open and a manual refresh action.
class PhotoCaptureCameraPickerScreen extends StatefulWidget {
  const PhotoCaptureCameraPickerScreen({
    super.key,
    required this.viewModel,
  });

  final CaptureViewModel viewModel;

  @override
  State<PhotoCaptureCameraPickerScreen> createState() =>
      _PhotoCaptureCameraPickerScreenState();
}

class _PhotoCaptureCameraPickerScreenState
    extends State<PhotoCaptureCameraPickerScreen> {
  Future<Map<String, UvcCameraDevice>>? _uvcDevicesFuture;
  StreamSubscription<UvcCameraDeviceEvent>? _uvcDeviceEventsSub;
  String? _uvcDebugLine;
  Timer? _uvcRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _attachUvcDeviceEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshCameras());
    });
  }

  @override
  void dispose() {
    _uvcRefreshDebounce?.cancel();
    _uvcRefreshDebounce = null;
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = null;
    super.dispose();
  }

  void _attachUvcDeviceEvents() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = UvcCamera.deviceEventStream.listen(
      (e) {
        AppLogger.debug(
          '🔌 UVC device event: ${e.type.name} '
          'name="${e.device.name}" vid=${e.device.vendorId} pid=${e.device.productId} '
          'class=${e.device.deviceClass} subclass=${e.device.deviceSubclass}',
        );
        ErrorReportingManager.log(
          'UVC device event: ${e.type.name} '
          'name="${e.device.name}" vid=${e.device.vendorId} pid=${e.device.productId}',
        );
        // Refresh the list on hotplug (debounced; some devices flap quickly).
        _uvcRefreshDebounce?.cancel();
        _uvcRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          unawaited(_refreshUvcOnly());
        });
      },
      onError: (err, st) {
        AppLogger.error('UVC deviceEventStream error', error: err, stackTrace: st);
      },
    );
  }

  Future<void> _refreshCameras() async {
    await widget.viewModel.refreshCameraEnumeration();
    await _refreshUvcOnly();
    if (mounted) setState(() {});
  }

  Future<void> _refreshUvcOnly() async {
    _uvcDevicesFuture = _loadUvcDevices();
    if (mounted) setState(() {});
  }

  Future<Map<String, UvcCameraDevice>> _loadUvcDevices() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _uvcDebugLine = 'uvc: not-android';
      return <String, UvcCameraDevice>{};
    }
    try {
      final supported = await UvcCamera.isSupported();
      if (!supported) {
        _uvcDebugLine = 'uvc: not-supported';
        AppLogger.debug('UVC: isSupported=false');
        return <String, UvcCameraDevice>{};
      }
      final devices = await UvcCamera.getDevices();
      final list = devices.values
          .map(
            (d) =>
                '"${d.name}" vid=${d.vendorId} pid=${d.productId} cls=${d.deviceClass}/${d.deviceSubclass}',
          )
          .join(' | ');
      _uvcDebugLine = 'uvc: supported devices=${devices.length}';
      AppLogger.debug('UVC devices (${devices.length}): $list');
      unawaited(ErrorReportingManager.setCustomKeys({
        'uvc_supported': true,
        'uvc_device_count': devices.length,
        'uvc_devices': list,
      }));
      return devices;
    } catch (e, st) {
      _uvcDebugLine = 'uvc: ERROR $e';
      AppLogger.error('UVC getDevices failed', error: e, stackTrace: st);
      unawaited(
        ErrorReportingManager.recordError(
          e,
          st,
          reason: 'UVC getDevices failed',
          fatal: false,
        ),
      );
      return <String, UvcCameraDevice>{};
    }
  }

  void _selectCamera(CameraDescription camera) {
    final vm = widget.viewModel;
    if (vm.currentCamera?.name == camera.name) return;
    Navigator.pop(context, camera);
  }

  void _selectUvcDevice(UvcCameraDevice device) {
    Navigator.pop(context, device);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final uniqueCameras = uniqueCamerasByDisplayName(
          vm.availableCameras,
          vm.getCameraDisplayName,
        );
        final usbHint = cameraPickerUsbHint(
          deviceType: vm.deviceType,
          cameras: vm.availableCameras,
        );
        final isRefreshing = vm.isLoadingCameras;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text(AppStrings.selectCameraTitle),
            leading: IconButton(
              icon: const Icon(CupertinoIcons.xmark),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_clockwise),
                tooltip: AppStrings.refreshCameras,
                onPressed: isRefreshing ? null : () => unawaited(_refreshCameras()),
              ),
            ],
          ),
          body: SafeArea(
            child: _buildBody(
              uniqueCameras: uniqueCameras,
              usbHint: usbHint,
              isRefreshing: isRefreshing,
              currentCameraName: vm.currentCamera?.name,
              displayNameFor: vm.getCameraDisplayName,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody({
    required List<CameraDescription> uniqueCameras,
    required String? usbHint,
    required bool isRefreshing,
    required String? currentCameraName,
    required String Function(CameraDescription camera) displayNameFor,
  }) {
    if (isRefreshing && uniqueCameras.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(AppStrings.cameraPickerRefreshing),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (usbHint != null) _buildHintBanner(usbHint),
        ..._buildUvcSection(),
        if (uniqueCameras.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppStrings.cameraPickerNoCameras,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          ...uniqueCameras.map((camera) {
            final isActive = currentCameraName == camera.name;
            final displayName = displayNameFor(camera);
            return ListTile(
              title: Text(displayName),
              leading: isActive
                  ? const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.blue,
                    )
                  : null,
              onTap: () => _selectCamera(camera),
            );
          }),
      ],
    );
  }

  List<Widget> _buildUvcSection() {
    if (defaultTargetPlatform != TargetPlatform.android) return const <Widget>[];
    _uvcDevicesFuture ??= _loadUvcDevices();

    return <Widget>[
      FutureBuilder<Map<String, UvcCameraDevice>>(
        future: _uvcDevicesFuture,
        builder: (context, snap) {
          final devices = snap.data ?? const <String, UvcCameraDevice>{};
          final hasDevices = devices.isNotEmpty;
          return Column(
            children: [
              ListTile(
                title: const Text(AppStrings.cameraPickerUsbCameraTitle),
                subtitle: hasDevices
                    ? Text('${devices.length} device(s) detected')
                    : Text(
                        _uvcDebugLine == null
                            ? AppStrings.cameraPickerUsbNoDevices
                            : '${AppStrings.cameraPickerUsbNoDevices}\n$_uvcDebugLine',
                      ),
                trailing: const Icon(CupertinoIcons.chevron_right),
                enabled: hasDevices,
                onTap: !hasDevices
                    ? null
                    : () => _selectUvcDevice(devices.values.first),
              ),
              const Divider(height: 1),
            ],
          );
        },
      ),
    ];
  }

  Widget _buildHintBanner(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
