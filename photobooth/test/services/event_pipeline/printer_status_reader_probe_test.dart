import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/printer_consumables.dart';
import 'package:photobooth/services/dnp/dnp_usb_client.dart';
import 'package:photobooth/services/event_pipeline/printer_status_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late MethodChannel channel;

  /// `getPrinterStatus` needs an open connection, which the native side only
  /// creates when permission is requested — so it answers NO_PRINTER both when
  /// nothing is plugged in and when a printer is sitting there unopened.
  void handleWith({required bool present, bool statusWorks = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getPrinterStatus':
          if (statusWorks) {
            return <Object?, Object?>{'status': 0, 'name': 'DS-RX1'};
          }
          throw PlatformException(code: 'NO_PRINTER', message: 'not connected');
        case 'probeDevice':
          return present;
        case 'requestPermission':
          return true;
      }
      return null;
    });
  }

  setUp(() {
    calls = <MethodCall>[];
    channel = const MethodChannel('com.srisarani.fotozenai/dnp_usb');
  });

  /// Presence and connect go through the kiosk's own [DnpUsbClient], which
  /// short-circuits off Android — so the test has to say it is on one.
  PrinterStatusReader reader() => PrinterStatusReader(
        channel: channel,
        usbClient: DnpUsbClient(channel: channel, isAndroid: () => true),
      );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a printer on the bus is opened rather than reported absent', () async {
    // handleWith keeps the status failing even after opening, which stands in
    // for a printer that is present but cannot be talked to.
    handleWith(present: true);
    final result = await reader().read();
    expect(result.readiness, PrinterReadiness.needsPermission);
    expect(calls.map((c) => c.method),
        ['getPrinterStatus', 'probeDevice', 'requestPermission', 'getPrinterStatus']);
  });

  test('nothing on the bus is genuinely offline', () async {
    handleWith(present: false);
    final result = await reader().read();
    expect(result.readiness, PrinterReadiness.offline);
  });

  test('an open printer is read normally, with no probe needed', () async {
    handleWith(present: true, statusWorks: true);
    final result = await reader().read();
    expect(result.readiness, PrinterReadiness.ready);
    expect(calls.map((c) => c.method), ['getPrinterStatus'],
        reason: 'the probe is only the tie-breaker for NO_PRINTER');
  });

  test('a probe that itself fails falls back to offline', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPrinterStatus') {
        throw PlatformException(code: 'NO_PRINTER');
      }
      throw PlatformException(code: 'BOOM');
    });
    final result = await reader().read();
    expect(result.readiness, PrinterReadiness.offline);
  });

  test('requesting permission is what opens the printer', () async {
    handleWith(present: true);
    expect(await reader().requestPermission(),
        isTrue);
    expect(calls.single.method, 'requestPermission');
  });

  test('a refused permission request is reported, not thrown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'DENIED', message: 'user said no');
    });
    expect(await reader().requestPermission(),
        isFalse);
  });

  test('off Android nothing is probed and the printer reads offline', () async {
    // The kiosk client short-circuits on web and desktop, which is why
    // presence belongs to it rather than to a second implementation here.
    handleWith(present: true);
    final result = await PrinterStatusReader(
      channel: channel,
      usbClient: DnpUsbClient(channel: channel, isAndroid: () => false),
    ).read();

    expect(result.readiness, PrinterReadiness.offline);
    // The status read still happens — it is the presence probe that is
    // pointless off Android, and skipping it is what makes this offline.
    expect(calls.map((c) => c.method), ['getPrinterStatus']);
  });
}
