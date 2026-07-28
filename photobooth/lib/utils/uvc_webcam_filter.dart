import 'package:uvccamera/uvccamera.dart';

/// DNP DS-RX1(S)HS vendor id (matches native [DnpUsbPrinter.kt]).
const int kDnpPrinterUsbVendorId = 0x1343;

/// USB device class constants for non-camera peripherals.
const int kUsbDeviceClassPrinter = 7;
const int kUsbDeviceClassHub = 9;

/// True when [device] is a UVC webcam — excludes DNP printers and other USB gear.
bool isUvcWebcamDevice(UvcCameraDevice device) {
  if (device.vendorId == kDnpPrinterUsbVendorId) return false;
  if (device.deviceClass == kUsbDeviceClassPrinter ||
      device.deviceClass == kUsbDeviceClassHub) {
    return false;
  }
  // UVC IAD (Misc + Common) or legacy Video class.
  if (device.deviceClass == 239 && device.deviceSubclass == 2) return true;
  if (device.deviceClass == 14) return true;
  // Per-interface class (common for UVC webcams); blocklist above catches DNP.
  if (device.deviceClass == 0) return true;
  return false;
}

/// Keeps only attached devices that look like UVC webcams.
Iterable<UvcCameraDevice> filterUvcWebcamDevices(
  Iterable<UvcCameraDevice> devices,
) {
  return devices.where(isUvcWebcamDevice);
}

bool hasUvcWebcamDevices(Map<String, UvcCameraDevice> devices) {
  return filterUvcWebcamDevices(devices.values).isNotEmpty;
}
