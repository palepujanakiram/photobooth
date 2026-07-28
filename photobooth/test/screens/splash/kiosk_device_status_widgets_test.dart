import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_device_status.dart';
import 'package:photobooth/screens/splash/kiosk_device_status_widgets.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/views/widgets/app_colors.dart';

void main() {
  testWidgets('KioskDeviceStatusRow shows connected USB labels', (tester) async {
    const entry = KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceDnpPrinter,
      connected: true,
      transport: KioskDeviceTransport.usb,
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return KioskDeviceStatusRow(
              entry: entry,
              appColors: AppColors.of(context),
            );
          },
        ),
      ),
    );
    expect(find.textContaining(AppStrings.kioskDeviceDnpPrinter), findsOneWidget);
    expect(find.textContaining(AppStrings.kioskDeviceConnected), findsOneWidget);
    expect(find.textContaining(AppStrings.kioskDeviceTransportUsb), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
  });

  testWidgets('KioskDeviceStatusRow shows not configured warning', (tester) async {
    const entry = KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceReceiptPrinter,
      connected: false,
      configured: false,
      transport: KioskDeviceTransport.wifi,
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return KioskDeviceStatusRow(
              entry: entry,
              appColors: AppColors.of(context),
            );
          },
        ),
      ),
    );
    expect(
      find.textContaining(AppStrings.kioskDeviceNotConfigured),
      findsOneWidget,
    );
    expect(
      find.byIcon(CupertinoIcons.exclamationmark_circle_fill),
      findsOneWidget,
    );
  });
}
