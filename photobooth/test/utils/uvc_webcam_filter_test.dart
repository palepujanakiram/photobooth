import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/uvc_webcam_filter.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  const dnpPrinter = UvcCameraDevice(
    name: 'DNP DS-RX1HS',
    vendorId: kDnpPrinterUsbVendorId,
    productId: 0x0005,
    deviceClass: 0,
    deviceSubclass: 0,
  );

  const uvcWebcam = UvcCameraDevice(
    name: 'Logitech Webcam',
    vendorId: 0x046d,
    productId: 0x0825,
    deviceClass: 239,
    deviceSubclass: 2,
  );

  const legacyVideoClass = UvcCameraDevice(
    name: 'USB Camera',
    vendorId: 0x1234,
    productId: 0x5678,
    deviceClass: 14,
    deviceSubclass: 0,
  );

  const compositeWebcam = UvcCameraDevice(
    name: 'Generic UVC',
    vendorId: 0x046d,
    productId: 0x0990,
    deviceClass: 0,
    deviceSubclass: 0,
  );

  const usbPrinter = UvcCameraDevice(
    name: 'Some Printer',
    vendorId: 0x9999,
    productId: 0x0001,
    deviceClass: kUsbDeviceClassPrinter,
    deviceSubclass: 0,
  );

  const usbHub = UvcCameraDevice(
    name: 'USB Hub',
    vendorId: 0x8888,
    productId: 0x0001,
    deviceClass: kUsbDeviceClassHub,
    deviceSubclass: 0,
  );

  const vendorSpecificCaptureCard = UvcCameraDevice(
    name: 'HDMI Capture',
    vendorId: 0x534d,
    productId: 0x2109,
    deviceClass: 255,
    deviceSubclass: 0,
  );

  const canonPtpDslr = UvcCameraDevice(
    name: 'Canon Digital Camera',
    vendorId: kCanonUsbVendorId,
    productId: 13033,
    deviceClass: 0,
    deviceSubclass: 0,
  );

  const appleNcmGadget = UvcCameraDevice(
    name: 'Mac',
    vendorId: kAppleUsbVendorId,
    productId: 6405,
    deviceClass: 0,
    deviceSubclass: 0,
  );

  const hidReceiver = UvcCameraDevice(
    name: 'USB Receiver',
    vendorId: 43173,
    productId: 8789,
    deviceClass: kUsbDeviceClassHid,
    deviceSubclass: 0,
  );

  test('isUvcWebcamDevice excludes DNP printer on USB', () {
    expect(isUvcWebcamDevice(dnpPrinter), isFalse);
  });

  test('isUvcWebcamDevice excludes Canon PTP and Apple NCM gadgets', () {
    expect(isUvcWebcamDevice(canonPtpDslr), isFalse);
    expect(isUvcWebcamDevice(appleNcmGadget), isFalse);
    expect(isUvcWebcamDevice(hidReceiver), isFalse);
  });

  test('isUvcWebcamDevice accepts UVC IAD and Video class devices', () {
    expect(isUvcWebcamDevice(uvcWebcam), isTrue);
    expect(isUvcWebcamDevice(legacyVideoClass), isTrue);
    expect(isUvcWebcamDevice(compositeWebcam), isTrue);
  });

  test('isUvcWebcamDevice accepts vendor-specific HDMI capture cards', () {
    expect(isUvcWebcamDevice(vendorSpecificCaptureCard), isTrue);
  });

  test('isUvcWebcamDevice excludes CDC and still-imaging classes', () {
    expect(
      isUvcWebcamDevice(
        const UvcCameraDevice(
          name: 'CDC NCM',
          vendorId: 0x1d6b,
          productId: 0x0100,
          deviceClass: kUsbDeviceClassCdc,
          deviceSubclass: 0,
        ),
      ),
      isFalse,
    );
    expect(
      isUvcWebcamDevice(
        const UvcCameraDevice(
          name: 'PTP Camera',
          vendorId: 0x04b0,
          productId: 0x0422,
          deviceClass: kUsbDeviceClassStillImaging,
          deviceSubclass: 1,
        ),
      ),
      isFalse,
    );
  });

  test('isUvcWebcamDevice accepts other USB classes as capture-capable', () {
    expect(
      isUvcWebcamDevice(
        const UvcCameraDevice(
          name: 'Misc IAD non-UVC',
          vendorId: 0x1111,
          productId: 0x2222,
          deviceClass: 239,
          deviceSubclass: 0,
        ),
      ),
      isTrue,
    );
  });

  test('isUvcWebcamDevice excludes printer, hub, and mass storage classes', () {
    expect(isUvcWebcamDevice(usbPrinter), isFalse);
    expect(isUvcWebcamDevice(usbHub), isFalse);
    expect(
      isUvcWebcamDevice(
        const UvcCameraDevice(
          name: 'USB Disk',
          vendorId: 0x0781,
          productId: 0x5567,
          deviceClass: kUsbDeviceClassMassStorage,
          deviceSubclass: 0,
        ),
      ),
      isFalse,
    );
  });

  test('hasUvcWebcamDevices false when only Canon PTP attached', () {
    expect(
      hasUvcWebcamDevices({'canon': canonPtpDslr}),
      isFalse,
    );
  });

  test('hasUvcWebcamDevices false when only DNP attached', () {
    expect(
      hasUvcWebcamDevices({'dnp': dnpPrinter}),
      isFalse,
    );
  });

  test('hasUvcWebcamDevices true when webcam present among USB devices', () {
    expect(
      hasUvcWebcamDevices({
        'dnp': dnpPrinter,
        'cam': uvcWebcam,
      }),
      isTrue,
    );
  });
}
