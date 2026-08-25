import '../../models/kiosk_device_status.dart';
import '../../utils/app_strings.dart';

/// Whether a kiosk-settings Device status row should be shown.
///
/// Canon Selphy and USB Camera stay probed in [KioskDeviceStatusService] but
/// are hidden until we are ready to surface them again.
bool kioskDeviceStatusRowEnabled(String deviceName) {
  switch (deviceName) {
    case AppStrings.kioskDeviceSelphyPrinter:
    case AppStrings.kioskDeviceUsbCamera:
      return false;
    default:
      return true;
  }
}

/// Guest-facing transport for a Device status row.
///
/// DNP and receipt printers are USB-only in the guest UI, matching DSLR.
String kioskDeviceStatusTransportLabel({
  required String deviceName,
  required KioskDeviceTransport? transport,
}) {
  if (deviceName == AppStrings.kioskDeviceDnpPrinter ||
      deviceName == AppStrings.kioskDeviceReceiptPrinter) {
    return AppStrings.kioskDeviceTransportUsb;
  }
  return switch (transport) {
    KioskDeviceTransport.usb => AppStrings.kioskDeviceTransportUsb,
    KioskDeviceTransport.wifi => AppStrings.kioskDeviceTransportWifi,
    KioskDeviceTransport.lan => AppStrings.kioskDeviceTransportLan,
    null => AppStrings.kioskDeviceTransportUnknown,
  };
}

/// Guest-facing connection state. Unattached devices are "Not connected",
/// never "Not configured".
String kioskDeviceStatusStateLabel(KioskDeviceStatusEntry entry) {
  if (entry.crashed) return AppStrings.kioskDeviceCrashed;
  if (entry.connected) return AppStrings.kioskDeviceConnected;
  return AppStrings.kioskDeviceNotConnected;
}
