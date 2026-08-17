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
const int kUsbDeviceClassVideo = 14;
const int kUsbDeviceClassMisc = 239;
const int kUsbDeviceClassVendorSpec = 255;

/// UVC IAD uses Misc (239) + Common (2).
const int kUsbMiscSubclassCommon = 2;

/// True when [device] is a UVC webcam — excludes DNP printers and other USB gear.
bool isUvcWebcamDevice(UvcCameraDevice device) {
  if (_isBlockedCaptureVendor(device.vendorId)) return false;
  if (_isNonCameraUsbClass(device.deviceClass)) return false;
  if (_isUvcVideoDeviceClass(device.deviceClass, device.deviceSubclass)) {
    return true;
  }
  if (device.deviceClass == kUsbDeviceClassVendorSpec) return true;
  if (device.deviceClass == 0) {
    return _perInterfaceLooksLikeUvcWebcam(device.interfaceClasses);
  }
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

bool _isBlockedCaptureVendor(int vendorId) {
  return vendorId == kDnpPrinterUsbVendorId ||
      vendorId == kCanonUsbVendorId ||
      vendorId == kAppleUsbVendorId;
}

bool _isNonCameraUsbClass(int usbClass) {
  return usbClass == kUsbDeviceClassPrinter ||
      usbClass == kUsbDeviceClassHub ||
      usbClass == kUsbDeviceClassCdc ||
      usbClass == kUsbDeviceClassHid ||
      usbClass == kUsbDeviceClassStillImaging ||
      usbClass == kUsbDeviceClassMassStorage;
}

bool _isUvcVideoDeviceClass(int deviceClass, int deviceSubclass) {
  if (deviceClass == kUsbDeviceClassMisc &&
      deviceSubclass == kUsbMiscSubclassCommon) {
    return true;
  }
  return deviceClass == kUsbDeviceClassVideo;
}

bool _isUvcCaptureInterfaceClass(int interfaceClass) {
  return interfaceClass == kUsbDeviceClassVideo ||
      interfaceClass == kUsbDeviceClassMisc ||
      interfaceClass == kUsbDeviceClassVendorSpec;
}

/// Class 0 (per-interface) HID dongles look like webcams until interfaces are
/// inspected. Empty [interfaceClasses] keeps the legacy "assume webcam" path
/// for unit tests and older native builds.
bool _perInterfaceLooksLikeUvcWebcam(List<int> interfaceClasses) {
  if (interfaceClasses.isEmpty) return true;
  return interfaceClasses.any(_isUvcCaptureInterfaceClass);
}
