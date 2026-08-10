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
  // Mass storage — not a capture card.
  if (device.deviceClass == 8) return false;
  // UVC IAD (Misc + Common) or legacy Video class.
  if (device.deviceClass == 239 && device.deviceSubclass == 2) return true;
  if (device.deviceClass == 14) return true;
  // Per-interface class (common for UVC webcams); blocklist above catches DNP.
  if (device.deviceClass == 0) return true;
  // Vendor-specific (0xFF) — many HDMI capture cards report this.
  if (device.deviceClass == 255) return true;
  // UVC plugin already lists camera-capable USB nodes; accept other classes
  // except the blocklist above so Terms/POSE do not miss odd capture cards.
  return true;
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
