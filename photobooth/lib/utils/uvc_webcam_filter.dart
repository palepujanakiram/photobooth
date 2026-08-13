import 'package:uvccamera/uvccamera.dart';

/// DNP DS-RX1(S)HS vendor id (matches native [DnpUsbPrinter.kt]).
const int kDnpPrinterUsbVendorId = 0x1343;

/// Canon PTP/EDSDK cameras — not UVC. Opening them via libuvc hangs POSE.
const int kCanonUsbVendorId = 0x04A9;

/// Apple USB gadgets (wireless-debug NCM) — not capture cards.
const int kAppleUsbVendorId = 0x05AC;

/// USB device class constants for non-camera peripherals.
const int kUsbDeviceClassCdc = 2;
const int kUsbDeviceClassHid = 3;
const int kUsbDeviceClassStillImaging = 6;
const int kUsbDeviceClassPrinter = 7;
const int kUsbDeviceClassMassStorage = 8;
const int kUsbDeviceClassHub = 9;

/// True when [device] is a UVC webcam — excludes DNP printers and other USB gear.
bool isUvcWebcamDevice(UvcCameraDevice device) {
  if (device.vendorId == kDnpPrinterUsbVendorId) return false;
  if (device.vendorId == kCanonUsbVendorId) return false;
  if (device.vendorId == kAppleUsbVendorId) return false;
  if (device.deviceClass == kUsbDeviceClassPrinter ||
      device.deviceClass == kUsbDeviceClassHub ||
      device.deviceClass == kUsbDeviceClassCdc ||
      device.deviceClass == kUsbDeviceClassHid ||
      device.deviceClass == kUsbDeviceClassStillImaging) {
    return false;
  }
  if (device.deviceClass == kUsbDeviceClassMassStorage) return false;
  // UVC IAD (Misc + Common) or legacy Video class.
  if (device.deviceClass == 239 && device.deviceSubclass == 2) return true;
  if (device.deviceClass == 14) return true;
  // Per-interface class (common for UVC webcams); blocklist above catches
  // Canon PTP, Apple NCM, DNP, HID.
  if (device.deviceClass == 0) return true;
  // Vendor-specific (0xFF) — many HDMI capture cards report this.
  if (device.deviceClass == 255) return true;
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
