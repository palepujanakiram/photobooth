import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_device_status.dart';
import 'package:photobooth/screens/splash/kiosk_device_status_visibility.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  test('kioskDeviceStatusRowEnabled hides Selphy and USB Camera', () {
    expect(
      kioskDeviceStatusRowEnabled(AppStrings.kioskDeviceSelphyPrinter),
      isFalse,
    );
    expect(
      kioskDeviceStatusRowEnabled(AppStrings.kioskDeviceUsbCamera),
      isFalse,
    );
  });

  test('kioskDeviceStatusRowEnabled keeps DNP, receipt, and DSLR', () {
    expect(
      kioskDeviceStatusRowEnabled(AppStrings.kioskDeviceDnpPrinter),
      isTrue,
    );
    expect(
      kioskDeviceStatusRowEnabled(AppStrings.kioskDeviceReceiptPrinter),
      isTrue,
    );
    expect(
      kioskDeviceStatusRowEnabled(AppStrings.kioskDeviceDslrSidecar),
      isTrue,
    );
  });

  test('kioskDeviceStatusTransportLabel is USB for DNP and receipt', () {
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceDnpPrinter,
        transport: KioskDeviceTransport.wifi,
      ),
      AppStrings.kioskDeviceTransportUsb,
    );
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        transport: KioskDeviceTransport.wifi,
      ),
      AppStrings.kioskDeviceTransportUsb,
    );
  });

  test('kioskDeviceStatusTransportLabel keeps probed value for DSLR', () {
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceDslrSidecar,
        transport: KioskDeviceTransport.usb,
      ),
      AppStrings.kioskDeviceTransportUsb,
    );
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceDslrSidecar,
        transport: KioskDeviceTransport.lan,
      ),
      AppStrings.kioskDeviceTransportLan,
    );
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        transport: KioskDeviceTransport.wifi,
      ),
      AppStrings.kioskDeviceTransportWifi,
    );
    expect(
      kioskDeviceStatusTransportLabel(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        transport: null,
      ),
      AppStrings.kioskDeviceTransportUnknown,
    );
  });

  test('kioskDeviceStatusStateLabel uses not connected when unattached', () {
    expect(
      kioskDeviceStatusStateLabel(
        const KioskDeviceStatusEntry(
          deviceName: AppStrings.kioskDeviceDslrSidecar,
          connected: false,
          configured: false,
          transport: KioskDeviceTransport.usb,
        ),
      ),
      AppStrings.kioskDeviceNotConnected,
    );
    expect(
      kioskDeviceStatusStateLabel(
        const KioskDeviceStatusEntry(
          deviceName: AppStrings.kioskDeviceReceiptPrinter,
          connected: false,
          configured: false,
          transport: KioskDeviceTransport.usb,
        ),
      ),
      AppStrings.kioskDeviceNotConnected,
    );
    expect(
      kioskDeviceStatusStateLabel(
        const KioskDeviceStatusEntry(
          deviceName: AppStrings.kioskDeviceDnpPrinter,
          connected: false,
          transport: KioskDeviceTransport.usb,
        ),
      ),
      AppStrings.kioskDeviceNotConnected,
    );
    expect(
      kioskDeviceStatusStateLabel(
        const KioskDeviceStatusEntry(
          deviceName: AppStrings.kioskDeviceDslrSidecar,
          connected: true,
          crashed: true,
          transport: KioskDeviceTransport.usb,
        ),
      ),
      AppStrings.kioskDeviceCrashed,
    );
    expect(
      kioskDeviceStatusStateLabel(
        const KioskDeviceStatusEntry(
          deviceName: AppStrings.kioskDeviceDslrSidecar,
          connected: true,
          transport: KioskDeviceTransport.usb,
        ),
      ),
      AppStrings.kioskDeviceConnected,
    );
  });
}
