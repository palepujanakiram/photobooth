import 'package:flutter/cupertino.dart';

import '../../models/kiosk_device_status.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';

/// Status rows shown under kiosk manage actions (DNP, receipt, USB, DSLR).
class KioskDeviceStatusPanel extends StatelessWidget {
  const KioskDeviceStatusPanel({
    super.key,
    required this.appColors,
    required this.loading,
    this.snapshot,
  });

  final AppColors appColors;
  final bool loading;
  final KioskDeviceStatusSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        if (loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: CupertinoActivityIndicator(color: appColors.primaryColor),
            ),
          )
        else if (snapshot != null) ...[
          KioskDeviceStatusRow(entry: snapshot!.dnpPrinter, appColors: appColors),
          const SizedBox(height: 8),
          KioskDeviceStatusRow(
            entry: snapshot!.receiptPrinter,
            appColors: appColors,
          ),
          const SizedBox(height: 8),
          KioskDeviceStatusRow(entry: snapshot!.usbCamera, appColors: appColors),
          const SizedBox(height: 8),
          KioskDeviceStatusRow(
            entry: snapshot!.dslrSidecar,
            appColors: appColors,
          ),
        ],
      ],
    );
  }
}

class KioskDeviceStatusRow extends StatelessWidget {
  const KioskDeviceStatusRow({
    super.key,
    required this.entry,
    required this.appColors,
  });

  final KioskDeviceStatusEntry entry;
  final AppColors appColors;

  @override
  Widget build(BuildContext context) {
    final ok = entry.configured && entry.connected;
    final icon = ok
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.exclamationmark_circle_fill;
    final iconColor = ok
        ? CupertinoColors.systemGreen.resolveFrom(context)
        : CupertinoColors.systemOrange.resolveFrom(context);
    final stateLabel = !entry.configured
        ? AppStrings.kioskDeviceNotConfigured
        : entry.connected
            ? AppStrings.kioskDeviceConnected
            : AppStrings.kioskDeviceNotConnected;
    final modeLabel = _transportLabel(entry.transport);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${entry.deviceName}  $stateLabel  $modeLabel',
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: appColors.textColor,
            ),
          ),
        ),
      ],
    );
  }

  String _transportLabel(KioskDeviceTransport? transport) {
    return switch (transport) {
      KioskDeviceTransport.usb => AppStrings.kioskDeviceTransportUsb,
      KioskDeviceTransport.wifi => AppStrings.kioskDeviceTransportWifi,
      KioskDeviceTransport.lan => AppStrings.kioskDeviceTransportLan,
      null => AppStrings.kioskDeviceTransportUnknown,
    };
  }
}
