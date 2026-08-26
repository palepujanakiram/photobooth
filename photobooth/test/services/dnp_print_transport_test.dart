import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/dnp/dnp_print_bridge.dart';
import 'package:photobooth/services/dnp/dnp_print_size.dart';
import 'package:photobooth/services/dnp/dnp_print_transport.dart';
import 'package:photobooth/services/dnp/dnp_usb_client.dart';
import 'package:photobooth/services/dnp/dnp_wifi_client.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/exceptions.dart';

class _RecordingUsbClient extends DnpUsbClient {
  _RecordingUsbClient(this.channel) : super(channel: channel);

  final MethodChannel channel;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int printCalls = 0;
  String? lastPaperSize;
  String? lastPrintSize;
  int? lastCopies;
  bool probePresent = true;
  PlatformException? connectError;
  PlatformException? printError;
  /// Fail this many [print] calls, then succeed (stale-write retry tests).
  int printFailuresBeforeSuccess = 0;

  @override
  Future<bool> probeDevicePresent() async => probePresent;

  @override
  Future<void> ensureConnected() async {
    if (connectError != null) throw connectError!;
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> print({
    required String filePath,
    required String paperSize,
    required String printSize,
    required int copies,
  }) async {
    if (printFailuresBeforeSuccess > 0) {
      printFailuresBeforeSuccess--;
      throw PlatformException(
        code: 'PRINT_ERROR',
        message: 'USB write failed at offset 0',
      );
    }
    if (printError != null) throw printError!;
    printCalls++;
    lastPaperSize = paperSize;
    lastPrintSize = printSize;
    lastCopies = copies;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DnpPrintSize.fromNetworkPrintSize', () {
    test('maps kiosk tokens to USB and Wi-Fi sizes', () {
      expect(
        DnpPrintSize.fromNetworkPrintSize(AppConstants.kPrintSizePortrait4x6),
        DnpPrintSize.portrait4x6,
      );
      expect(
        DnpPrintSize.fromNetworkPrintSize(AppConstants.kPrintSizeLandscape6x4),
        DnpPrintSize.landscape6x4,
      );
      expect(
        DnpPrintSize.fromNetworkPrintSize(AppConstants.kPrintSizeStripDual2x6),
        DnpPrintSize.stripDual6x2,
      );
      expect(DnpPrintSize.fromNetworkPrintSize('s5x7').usbLabel, '5x7');
      expect(DnpPrintSize.fromNetworkPrintSize(null).wifiPrintSize, 's4x6');
    });

    test('maps strip tokens to 4x6 USB paper with cutter on native side', () {
      expect(DnpPrintSize.fromNetworkPrintSize('s6x2_2').usbLabel, '4x6');
      expect(DnpPrintSize.fromNetworkPrintSize('s2x6').usbLabel, '4x6');
    });
  });

  group('resolveDnpPrintTransport', () {
    test('reads printerTransport from settings', () {
      expect(
        resolveDnpPrintTransport(AppSettingsModel(printerTransport: 'usb')),
        DnpPrintTransport.usb,
      );
      expect(
        resolveDnpPrintTransport(AppSettingsModel(printerTransport: 'wifi')),
        DnpPrintTransport.wifi,
      );
      expect(
        resolveDnpPrintTransport(AppSettingsModel(printerTransport: 'wcm_plus')),
        DnpPrintTransport.wifi,
      );
    });

    test('defaults to auto when unset or unknown', () {
      expect(resolveDnpPrintTransport(null), DnpPrintTransport.auto);
      expect(resolveDnpPrintTransport(AppSettingsModel()), DnpPrintTransport.auto);
      expect(
        resolveDnpPrintTransport(AppSettingsModel(printerTransport: 'unknown')),
        DnpPrintTransport.auto,
      );
      expect(
        resolveDnpPrintTransport(null, transportOverride: 'lan'),
        DnpPrintTransport.auto,
      );
    });

    test('admin printerTransport wins over printerHost alone', () {
      expect(
        resolveDnpPrintTransport(
          AppSettingsModel(printerHost: '192.168.0.155'),
        ),
        DnpPrintTransport.auto,
      );
      expect(
        resolveDnpPrintTransport(
          AppSettingsModel(
            printerHost: '192.168.0.155',
            printerTransport: 'auto',
          ),
        ),
        DnpPrintTransport.auto,
      );
      expect(
        resolveDnpPrintTransport(
          AppSettingsModel(
            printerHost: '192.168.0.155',
            printerTransport: 'usb',
          ),
        ),
        DnpPrintTransport.usb,
      );
      expect(
        resolveDnpPrintTransport(
          AppSettingsModel(
            printerHost: '192.168.0.155',
            printerTransport: 'wifi',
          ),
        ),
        DnpPrintTransport.wifi,
      );
    });

    test('honours transport override parameter', () {
      expect(
        resolveDnpPrintTransport(null, transportOverride: 'usb'),
        DnpPrintTransport.usb,
      );
      expect(
        resolveDnpPrintTransport(
          AppSettingsModel(printerTransport: 'wifi'),
          transportOverride: 'usb',
        ),
        DnpPrintTransport.usb,
      );
    });
  });

  group('DnpUsbClient', () {
    const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('hasUsbHost returns false when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await DnpUsbClient().hasUsbHost(), isFalse);
    });

    test('probeDevicePresent returns true when native probe succeeds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'probeDevice') return true;
        return null;
      });
      final client = DnpUsbClient(channel: channel, isAndroid: () => true);
      expect(await client.probeDevicePresent(), isTrue);
    });

    test('hasUsbHost returns true when channel succeeds on Android', () async {
      const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final client = DnpUsbClient(channel: channel, isAndroid: () => true);
      expect(await client.hasUsbHost(), isTrue);
    });

    test('ensureConnected, disconnect and print invoke native methods', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final client = DnpUsbClient(channel: channel, isAndroid: () => true);
      await client.ensureConnected();
      await client.disconnect();
      await client.print(
        filePath: '/tmp/a.jpg',
        paperSize: '4x6',
        printSize: 's4x6',
        copies: 2,
      );
      expect(calls, ['requestPermission', 'disconnect', 'print']);
    });
  });

  group('DnpWifiClient', () {
    test('discoverOnPrefix finds first WCM Plus host', () async {
      final client = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.host == '192.168.2.108') {
            return http.Response('{}', 200);
          }
          return http.Response('', 404);
        }),
      );
      final url = await client.discoverOnPrefix('192.168.2', parallelism: 32);
      expect(url, 'http://192.168.2.108');
      expect(client.printerBaseUrl, url);
    });

    test('print throws when WCM Plus base URL is unset', () async {
      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_no_base_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });
      expect(
        () => client.print(jpegFile: jpeg, printSize: 's4x6', copies: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('print posts to PrintImage when base URL is set', () async {
      var hitPrint = false;
      final client = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            hitPrint = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      client.printerBaseUrlForTesting = 'http://10.0.0.5';
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_test_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8, 0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await client.print(jpegFile: jpeg, printSize: 's4x6', copies: 2);
      expect(hitPrint, isTrue);
    });

    test('print throws on non-success HTTP status', () async {
      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('fail', 500)),
      );
      client.printerBaseUrlForTesting = 'http://10.0.0.5';
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_http_fail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });
      expect(
        () => client.print(jpegFile: jpeg, printSize: 's4x6', copies: 1),
        throwsStateError,
      );
    });

    test('print invokes progress callback for each copy', () async {
      final stages = <String>[];
      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      client.printerBaseUrlForTesting = 'http://10.0.0.5';
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_progress_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await client.print(
        jpegFile: jpeg,
        printSize: 's4x6',
        copies: 2,
        onProgress: (stage, _, __) => stages.add(stage),
      );
      expect(stages, contains('wifi_upload'));
      expect(stages.last, 'complete');
    });

    test('discoverFn can short-circuit subnet scan', () async {
      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('', 404)),
        discoverFn: ({int parallelism = 20}) async => 'http://192.168.9.9',
      );
      final url = await client.discover();
      expect(url, 'http://192.168.9.9');
      expect(client.printerBaseUrl, url);
    });

    test('discoverOnPrefix returns null when subnet has no WCM Plus', () async {
      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final url = await client.discoverOnPrefix('10.255.255', parallelism: 8);
      expect(url, isNull);
    });

    test('discover returns null when device has no Wi-Fi IP', () async {
      const networkInfoChannel =
          MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(networkInfoChannel, (call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(networkInfoChannel, null);
      });

      final client = DnpWifiClient(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final url = await client.discover(parallelism: 8);
      expect(url, isNull);
    });

    test('discover uses local Wi-Fi IP when discoverFn is unset', () async {
      const networkInfoChannel =
          MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(networkInfoChannel, (call) async {
        if (call.method == 'wifiIPAddress') return '192.168.2.100';
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(networkInfoChannel, null);
      });

      final client = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.host == '192.168.2.108') {
            return http.Response('{}', 200);
          }
          return http.Response('', 404);
        }),
      );
      final url = await client.discover(parallelism: 32);
      expect(url, 'http://192.168.2.108');
    });
  });

  group('DnpPrintBridge', () {
    test('resetSession clears wifi discovery and disconnects USB', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_reset'));
      final wifi = DnpWifiClient(client: MockClient((_) async => http.Response('', 404)));
      wifi.printerBaseUrlForTesting = 'http://10.0.0.1';
      final bridge = DnpPrintBridge(usbClient: usb, wifiClient: wifi);
      await bridge.resetSession();
      expect(wifi.printerBaseUrl, isNull);
      expect(usb.disconnectCalls, 1);
    });

    test('USB print retries once after stale write failure', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_retry'))
        ..printFailuresBeforeSuccess = 1;
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_retry_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'usb'),
        networkPrintSize: 's4x6',
      );
      expect(usb.connectCalls, 2);
      expect(usb.disconnectCalls, 1);
      expect(usb.printCalls, 1);
    });

    test('printImage uses USB on Android when transport is unset (auto default)', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'));
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_auto_default_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(),
        networkPrintSize: 's4x6',
      );
      expect(usb.connectCalls, 1);
      expect(usb.printCalls, 1);
    });

    test('auto transport completes USB print when probe finds device', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'));
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_auto_usb_ok_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'auto'),
        networkPrintSize: AppConstants.kPrintSizePortrait4x6,
        quantity: 2,
      );

      expect(usb.connectCalls, 1);
      expect(usb.printCalls, 1);
      expect(usb.lastPrintSize, AppConstants.kPrintSizePortrait4x6);
      expect(usb.lastCopies, 2);
    });

    test('auto transport uses Wi-Fi when USB probe finds no device', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'))
        ..probePresent = false;
      var printedWifi = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedWifi = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      wifi.printerBaseUrlForTesting = 'http://192.168.1.20';

      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_probe_miss_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'auto'),
        networkPrintSize: 's4x6',
      );
      expect(usb.printCalls, 0);
      expect(usb.connectCalls, 0);
      expect(printedWifi, isTrue);
    });

    test('auto transport falls back to Wi-Fi when USB print fails', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'))
        ..connectError = PlatformException(code: 'CONNECT_FAILED');
      var printedWifi = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedWifi = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      wifi.printerBaseUrlForTesting = 'http://192.168.1.20';

      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_fail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'auto'),
        networkPrintSize: 's4x6',
      );
      expect(usb.connectCalls, 0);
      expect(printedWifi, isTrue);
    });

    test('auto transport falls back to Wi-Fi when USB permission is refused',
        () async {
      // The refusal used to be silent: PERMISSION_DENIED is recoverable, so the
      // hunt moved on, and with no network printer the Print button did nothing.
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_denied'))
        ..connectError = PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'USB permission denied. Reconnect the printer and try again.',
        );
      var printedWifi = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedWifi = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      wifi.printerBaseUrlForTesting = 'http://192.168.1.20';

      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_denied_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'auto'),
        networkPrintSize: 's4x6',
      );

      expect(usb.printCalls, 0, reason: 'USB never became usable');
      expect(printedWifi, isTrue, reason: 'the hunt still reaches Wi-Fi');
    });

    test('usb-only transport surfaces a refused permission to the caller',
        () async {
      // With transport pinned to usb there is no hunt to absorb it, so the
      // refusal must reach the caller rather than resolving silently.
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_only'))
        ..connectError = PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'USB permission denied. Reconnect the printer and try again.',
        );
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(
          client: MockClient((_) async => http.Response('', 404)),
        ),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usbonly_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await expectLater(
        bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'usb'),
          networkPrintSize: 's4x6',
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );
      expect(usb.printCalls, 0);
    });

    test('printImage uses wifi when transport is wifi', () async {
      var printed = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printed = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      wifi.printerBaseUrlForTesting = 'http://192.168.1.20';

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_bridge_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      final bridge = DnpPrintBridge(wifiClient: wifi);
      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'wifi'),
        networkPrintSize: AppConstants.kPrintSizePortrait4x6,
      );
      expect(printed, isTrue);
    });

    test('printImage rejects empty local path', () async {
      final bridge = DnpPrintBridge(
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
      );
      expect(
        () => bridge.printImage(
          imageFile: XFile(''),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('printImage rejects http URL paths', () async {
      final bridge = DnpPrintBridge(
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
      );
      expect(
        () => bridge.printImage(
          imageFile: XFile('https://example.com/a.jpg'),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('printImage uses USB on Android when transport is usb', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'));
      final wifi = DnpWifiClient(client: MockClient((_) async => http.Response('', 404)));
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'usb'),
        networkPrintSize: AppConstants.kPrintSizeStripDual2x6,
        quantity: 2,
      );
      expect(usb.printCalls, 1);
      expect(usb.lastPaperSize, '4x6');
      expect(usb.lastPrintSize, AppConstants.kPrintSizeStripDual2x6);
      expect(usb.lastCopies, 2);
      expect(wifi.printerBaseUrl, isNull);
    });

    test('clamps copy count to kiosk max', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'));
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_clamp_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'usb'),
        networkPrintSize: 's4x6',
        quantity: 99,
      );
      expect(usb.lastCopies, AppConstants.kMaxPrintCopies);
    });

    test('reuses warm USB session for subsequent pages', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'));
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_warm_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'usb'),
        networkPrintSize: 's4x6',
      );
      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'usb'),
        networkPrintSize: 's4x6',
      );
      expect(usb.connectCalls, 1);
      expect(usb.printCalls, 2);
    });

    test('auto transport falls back to wifi when USB is unavailable', () async {
      const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestPermission') {
          throw PlatformException(code: 'NO_PRINTER');
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      var printedWifi = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedWifi = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
      );
      wifi.printerBaseUrlForTesting = 'http://192.168.0.50';

      final bridge = DnpPrintBridge(
        usbClient: DnpUsbClient(channel: channel),
        wifiClient: wifi,
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_fallback_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'auto'),
        networkPrintSize: 's4x6',
      );
      expect(printedWifi, isTrue);
    });

    test('rejects web platform', () async {
      final bridge = DnpPrintBridge(webUnsupported: true);
      expect(
        () => bridge.printImage(
          imageFile: XFile('/tmp/x.jpg'),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('USB transport uses default platform check (_defaultIsAndroid)',
        () async {
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_default_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      // No isAndroid inject — exercises _defaultIsAndroid.
      final bridge = DnpPrintBridge(
        usbClient: _RecordingUsbClient(const MethodChannel('test/usb_default')),
        wifiClient: DnpWifiClient(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      );

      // On non-Android hosts this throws USB-only-on-Android; on Android it
      // prints via the fake USB client. Either path calls _defaultIsAndroid.
      try {
        await bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'usb'),
          networkPrintSize: 's4x6',
        );
      } on PrintException catch (e) {
        expect(e.message, contains('Android'));
      }
    });

    test('USB transport rejects when isAndroid is false', () async {
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_non_android_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF, 0xD8]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      final bridge = DnpPrintBridge(
        usbClient: _RecordingUsbClient(const MethodChannel('test/usb_ios')),
        wifiClient: DnpWifiClient(
          client: MockClient((_) async => http.Response('', 404)),
        ),
        isAndroid: () => false,
      );

      await expectLater(
        bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'usb'),
          networkPrintSize: 's4x6',
        ),
        throwsA(
          isA<PrintException>().having(
            (e) => e.message,
            'message',
            contains('Android'),
          ),
        ),
      );
    });

    test('auto transport rethrows non-recoverable USB errors', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb'))
        ..printError = PlatformException(
          code: 'PRINT_ERROR',
          message: 'hardware fault',
        );
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_auto_err_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await expectLater(
        bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'auto'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(usb.printCalls, 0);
    });

    test('usb-only transport rethrows when device unavailable', () async {
      const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'NO_PRINTER', message: 'missing');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = DnpPrintBridge(
        usbClient: DnpUsbClient(channel: channel),
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
        isAndroid: () => true,
      );

      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_usb_fail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      expect(
        () => bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'usb'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('printImage rejects missing file', () async {
      final bridge = DnpPrintBridge(
        wifiClient: DnpWifiClient(client: MockClient((_) async => http.Response('', 404))),
      );
      expect(
        () => bridge.printImage(
          imageFile: XFile('/tmp/dnp_missing_${DateTime.now().millisecondsSinceEpoch}.jpg'),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });
  });

  group('prepareDnpWifiNetwork', () {
    const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns true on non-Android test VM', () async {
      expect(await prepareDnpWifiNetwork(), isTrue);
    });

    test('returns native bind result on Android', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepareWifiNetwork') return true;
        return null;
      });
      expect(await prepareDnpWifiNetwork(isAndroid: () => true), isTrue);
    });

    test('returns false when native bind fails on Android', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepareWifiNetwork') return false;
        return null;
      });
      expect(await prepareDnpWifiNetwork(isAndroid: () => true), isFalse);
    });

    test('returns false when native channel throws on Android', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await prepareDnpWifiNetwork(isAndroid: () => true), isFalse);
    });
  });

  group('DnpPrintBridge wifi discovery failure', () {
    test('throws when Android Wi-Fi bind fails and no fallback host', () async {
      final wifi = DnpWifiClient(
        client: MockClient((_) async => http.Response('', 404)),
        discoverFn: ({int parallelism = 20}) async => 'http://10.0.0.2',
      );
      final bridge = DnpPrintBridge(
        wifiClient: wifi,
        isAndroid: () => true,
        prepareWifiNetwork: () async => false,
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_bind_fail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      expect(
        () => bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test(
      'uses configured printerHost without bind or subnet discovery',
      () async {
        var printedHost = '';
        var discoverCalled = false;
        var prepareCalled = false;
        final wifi = DnpWifiClient(
          client: MockClient((request) async {
            if (request.url.path == '/api/PrintImage') {
              printedHost = request.url.host;
              return http.Response('ok', 200);
            }
            return http.Response('', 404);
          }),
          discoverFn: ({int parallelism = 20}) async {
            discoverCalled = true;
            return null;
          },
        );
        final bridge = DnpPrintBridge(
          wifiClient: wifi,
          isAndroid: () => true,
          prepareWifiNetwork: () async {
            prepareCalled = true;
            return false;
          },
        );
        final jpeg = File(
          '${Directory.systemTemp.path}/dnp_bind_fallback_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await jpeg.writeAsBytes([0xFF]);
        addTearDown(() async {
          if (await jpeg.exists()) await jpeg.delete();
        });

        await bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(
            printerTransport: 'wifi',
            printerHost: '192.168.0.155',
            printerPort: 80,
            printerPath: '/print',
          ),
          networkPrintSize: 's4x6',
        );

        expect(printedHost, '192.168.0.155');
        expect(discoverCalled, isFalse);
        expect(prepareCalled, isFalse);
        expect(wifi.printerBaseUrl, 'http://192.168.0.155');
      },
    );

    test('throws when WCM Plus cannot be discovered or configured', () async {
      final wifi = DnpWifiClient(
        client: MockClient((_) async => http.Response('', 404)),
        discoverFn: ({int parallelism = 20}) async => null,
      );
      final bridge = DnpPrintBridge(wifiClient: wifi, isAndroid: () => false);
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_no_wcm_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      expect(
        () => bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'wifi'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('discovers WCM Plus on Android when Wi-Fi bind succeeds', () async {
      var printedHost = '';
      var discoverCalled = false;
      var prepareCalled = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedHost = request.url.host;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
        discoverFn: ({int parallelism = 20}) async {
          discoverCalled = true;
          return 'http://192.168.3.20';
        },
      );
      final bridge = DnpPrintBridge(
        wifiClient: wifi,
        isAndroid: () => true,
        prepareWifiNetwork: () async {
          prepareCalled = true;
          return true;
        },
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_android_discover_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'wifi'),
        networkPrintSize: 's4x6',
      );

      expect(printedHost, '192.168.3.20');
      expect(discoverCalled, isTrue);
      expect(prepareCalled, isTrue);
      expect(wifi.printerBaseUrl, 'http://192.168.3.20');
    });

    test('auto prefers kiosk printerHost over USB when host is set', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_auto_ip'));
      var printedHost = '';
      var discoverCalled = false;
      var prepareCalled = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedHost = request.url.host;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
        discoverFn: ({int parallelism = 20}) async {
          discoverCalled = true;
          return 'http://192.168.3.20';
        },
      );
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
        prepareWifiNetwork: () async {
          prepareCalled = true;
          return true;
        },
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_host_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(
          printerTransport: 'auto',
          printerHost: '192.168.0.155',
          printerPort: 80,
          printerPath: '/print',
        ),
        networkPrintSize: 's4x6',
      );

      expect(usb.printCalls, 0);
      expect(printedHost, '192.168.0.155');
      expect(discoverCalled, isFalse);
      expect(prepareCalled, isFalse);
      expect(wifi.printerBaseUrl, 'http://192.168.0.155');
    });

    test('wifi mode skips USB even when USB device is present', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_host_ip'));
      var printedHost = '';
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedHost = request.url.host;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
        discoverFn: ({int parallelism = 20}) async => 'http://192.168.3.20',
      );
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_skip_usb_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(
          printerTransport: 'wifi',
          printerHost: '192.168.0.155',
        ),
        networkPrintSize: 's4x6',
      );

      expect(usb.printCalls, 0);
      expect(usb.connectCalls, 0);
      expect(printedHost, '192.168.0.155');
    });

    test('auto falls back to USB when kiosk printerHost print fails', () async {
      final usb = _RecordingUsbClient(const MethodChannel('test/usb_auto_fallback'));
      var wifiAttempts = 0;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            wifiAttempts++;
            return http.Response('down', 500);
          }
          return http.Response('', 404);
        }),
      );
      final bridge = DnpPrintBridge(
        usbClient: usb,
        wifiClient: wifi,
        isAndroid: () => true,
      );
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_auto_ip_fail_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(
          printerTransport: 'auto',
          printerHost: '192.168.0.155',
        ),
        networkPrintSize: 's4x6',
      );

      expect(wifiAttempts, 1);
      expect(usb.printCalls, 1);
    });

    test('discovers WCM Plus on first wifi print when base URL unset', () async {
      var printedWifi = false;
      final wifi = DnpWifiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/PrintImage') {
            printedWifi = true;
            return http.Response('ok', 200);
          }
          return http.Response('', 404);
        }),
        discoverFn: ({int parallelism = 20}) async => 'http://192.168.3.20',
      );
      final bridge = DnpPrintBridge(wifiClient: wifi, isAndroid: () => false);
      final jpeg = File(
        '${Directory.systemTemp.path}/dnp_discover_ok_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      await bridge.printImage(
        imageFile: XFile(jpeg.path),
        settings: AppSettingsModel(printerTransport: 'wifi'),
        networkPrintSize: 's4x6',
      );
      expect(printedWifi, isTrue);
      expect(wifi.printerBaseUrl, 'http://192.168.3.20');
    });
  });
}
