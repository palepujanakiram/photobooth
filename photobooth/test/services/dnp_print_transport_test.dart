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
  int printCalls = 0;
  String? lastPaperSize;
  String? lastPrintSize;
  int? lastCopies;

  @override
  Future<void> ensureConnected() async {
    connectCalls++;
  }

  @override
  Future<void> print({
    required String filePath,
    required String paperSize,
    required String printSize,
    required int copies,
  }) async {
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

    test('defaults to usb when unset or unknown', () {
      expect(resolveDnpPrintTransport(null), DnpPrintTransport.usb);
      expect(resolveDnpPrintTransport(AppSettingsModel()), DnpPrintTransport.usb);
      expect(
        resolveDnpPrintTransport(AppSettingsModel(printerTransport: 'unknown')),
        DnpPrintTransport.usb,
      );
      expect(
        resolveDnpPrintTransport(null, transportOverride: 'lan'),
        DnpPrintTransport.usb,
      );
    });

    test('honours transport override parameter', () {
      expect(
        resolveDnpPrintTransport(null, transportOverride: 'usb'),
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

    test('ensureConnected and print invoke native methods', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final client = DnpUsbClient(channel: channel);
      await client.ensureConnected();
      await client.print(
        filePath: '/tmp/a.jpg',
        paperSize: '4x6',
        printSize: 's4x6',
        copies: 2,
      );
      expect(calls, ['requestPermission', 'print']);
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
    test('resetSession clears wifi discovery', () {
      final wifi = DnpWifiClient(client: MockClient((_) async => http.Response('', 404)));
      wifi.printerBaseUrlForTesting = 'http://10.0.0.1';
      final bridge = DnpPrintBridge(wifiClient: wifi);
      bridge.resetSession();
      expect(wifi.printerBaseUrl, isNull);
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

    test('auto transport rethrows non-recoverable USB errors', () async {
      const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'PRINT_ERROR', message: 'hardware fault');
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
        '${Directory.systemTemp.path}/dnp_auto_err_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await jpeg.writeAsBytes([0xFF]);
      addTearDown(() async {
        if (await jpeg.exists()) await jpeg.delete();
      });

      expect(
        () => bridge.printImage(
          imageFile: XFile(jpeg.path),
          settings: AppSettingsModel(printerTransport: 'auto'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PlatformException>()),
      );
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
    test('throws when Android Wi-Fi bind fails before discovery', () async {
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

    test('throws when WCM Plus cannot be discovered', () async {
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
