import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings_model.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/canon_usb_permission.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/route_args.dart';
import 'direct_ptp_capture_view.dart';
import 'photo_capture_view.dart';

/// Probes whether a Canon DSLR is attached for native PTP capture.
typedef DirectPtpHardwareProbe = Future<bool> Function({
  AppSettingsModel? settings,
});

/// Test hook: when set, [CaptureScreenRouter] skips the async USB probe.
@visibleForTesting
DirectPtpHardwareProbe? directPtpHardwareProbeOverride;

Future<bool> _defaultDirectPtpHardwareProbe({
  AppSettingsModel? settings,
}) =>
    isDirectPtpHardwareAvailable(settings: settings);

/// Chooses [DirectPtpCaptureScreen] vs [PhotoCaptureScreen] at runtime.
///
/// ZenAI may configure `direct_ptp` even on dev tablets without a DSLR — probe
/// USB before handing POSE to the native PTP Activity.
class CaptureScreenRouter extends StatefulWidget {
  const CaptureScreenRouter({
    super.key,
    required this.sessionKind,
    this.captureArgs,
    this.settings,
    this.hardwareProbe,
  });

  final CaptureSessionKind sessionKind;
  final CaptureRouteArgs? captureArgs;
  final AppSettingsModel? settings;
  final DirectPtpHardwareProbe? hardwareProbe;

  @override
  State<CaptureScreenRouter> createState() => _CaptureScreenRouterState();
}

class _CaptureScreenRouterState extends State<CaptureScreenRouter> {
  Widget? _resolved;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final settings = widget.settings ?? _settingsFromContext(context);
    final probe = directPtpHardwareProbeOverride ??
        widget.hardwareProbe ??
        _defaultDirectPtpHardwareProbe;
    final hardwarePresent = await probe(settings: settings);
    if (!mounted) return;
    setState(() {
      _resolved = hardwarePresent
          ? DirectPtpCaptureScreen(
              sessionKind: widget.sessionKind,
              captureArgs: widget.captureArgs,
            )
          : PhotoCaptureScreen(
              sessionKind: widget.sessionKind,
              captureArgs: widget.captureArgs,
            );
    });
  }

  AppSettingsModel? _settingsFromContext(BuildContext context) {
    try {
      return context.read<AppSettingsManager>().settings;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _resolved;
    if (child != null) return child;
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
