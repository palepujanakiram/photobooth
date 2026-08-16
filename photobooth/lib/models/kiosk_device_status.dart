/// Connection transport label for kiosk hardware status rows.
enum KioskDeviceTransport {
  usb,
  wifi,
  lan,
}

/// One hardware row on the kiosk settings screen.
class KioskDeviceStatusEntry {
  const KioskDeviceStatusEntry({
    required this.deviceName,
    required this.connected,
    required this.transport,
    this.configured = true,
    this.crashed = false,
  });

  final String deviceName;
  final bool connected;

  /// When false (e.g. receipt printer disabled), UI shows "Not configured".
  final bool configured;

  /// True when the sidecar process started but exited unexpectedly.
  final bool crashed;

  final KioskDeviceTransport? transport;
}

/// Snapshot of photo printers, receipt, USB camera, and Pi DSLR connectivity.
class KioskDeviceStatusSnapshot {
  const KioskDeviceStatusSnapshot({
    required this.dnpPrinter,
    required this.selphyPrinter,
    required this.receiptPrinter,
    required this.usbCamera,
    required this.dslrSidecar,
  });

  final KioskDeviceStatusEntry dnpPrinter;
  final KioskDeviceStatusEntry selphyPrinter;
  final KioskDeviceStatusEntry receiptPrinter;
  final KioskDeviceStatusEntry usbCamera;
  final KioskDeviceStatusEntry dslrSidecar;
}
