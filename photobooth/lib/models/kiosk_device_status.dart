/// Connection transport label for kiosk hardware status rows.
enum KioskDeviceTransport {
  usb,
  wifi,
}

/// One hardware row on the kiosk settings screen.
class KioskDeviceStatusEntry {
  const KioskDeviceStatusEntry({
    required this.deviceName,
    required this.connected,
    required this.transport,
    this.configured = true,
  });

  final String deviceName;
  final bool connected;

  /// When false (e.g. receipt printer disabled), UI shows "Not configured".
  final bool configured;
  final KioskDeviceTransport? transport;
}

/// Snapshot of DNP, receipt, and USB camera connectivity.
class KioskDeviceStatusSnapshot {
  const KioskDeviceStatusSnapshot({
    required this.dnpPrinter,
    required this.receiptPrinter,
    required this.usbCamera,
  });

  final KioskDeviceStatusEntry dnpPrinter;
  final KioskDeviceStatusEntry receiptPrinter;
  final KioskDeviceStatusEntry usbCamera;
}
