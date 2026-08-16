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

  testWidgets('KioskDeviceStatusRow shows crashed state with red icon even when USB present', (tester) async {
    // Camera is physically connected (connected: true) but sidecar crashed.
    // Must show red, not green.
    const entry = KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceDslrSidecar,
      connected: true,
      crashed: true,
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
    expect(find.textContaining(AppStrings.kioskDeviceCrashed), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.xmark_circle_fill), findsOneWidget);
  });

  testWidgets('KioskDeviceStatusPanel shows DSLR USB row', (tester) async {
    const snapshot = KioskDeviceStatusSnapshot(
      dnpPrinter: KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceDnpPrinter,
        connected: true,
        transport: KioskDeviceTransport.usb,
      ),
      selphyPrinter: KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        connected: false,
        transport: KioskDeviceTransport.usb,
      ),
      receiptPrinter: KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: false,
        configured: false,
        transport: KioskDeviceTransport.wifi,
      ),
      usbCamera: KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        connected: false,
        transport: KioskDeviceTransport.usb,
      ),
      dslrSidecar: KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceDslrSidecar,
        connected: true,
        transport: KioskDeviceTransport.usb,
      ),
    );
    var refreshTaps = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return KioskDeviceStatusPanel(
              appColors: AppColors.of(context),
              loading: false,
              snapshot: snapshot,
              onRefresh: () => refreshTaps++,
            );
          },
        ),
      ),
    );
    expect(find.textContaining(AppStrings.kioskDeviceDslrSidecar), findsOneWidget);
    expect(find.textContaining(AppStrings.kioskDeviceSelphyPrinter), findsOneWidget);
    // DSLR row includes "Connected" and "USB" — verify the full combined text.
    expect(
      find.textContaining(
        '${AppStrings.kioskDeviceDslrSidecar}  ${AppStrings.kioskDeviceConnected}  ${AppStrings.kioskDeviceTransportUsb}',
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.kioskDeviceStatusHeading), findsOneWidget);
    expect(find.text(AppStrings.kioskDeviceStatusRefresh), findsOneWidget);
    await tester.tap(find.text(AppStrings.kioskDeviceStatusRefresh));
    await tester.pump();
    expect(refreshTaps, 1);
  });

  testWidgets('KioskDeviceStatusPanel disables refresh while loading', (
    tester,
  ) async {
    var refreshTaps = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return KioskDeviceStatusPanel(
              appColors: AppColors.of(context),
              loading: true,
              onRefresh: () => refreshTaps++,
            );
          },
        ),
      ),
    );
    await tester.tap(find.text(AppStrings.kioskDeviceStatusRefresh));
    await tester.pump();
    expect(refreshTaps, 0);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });
}
