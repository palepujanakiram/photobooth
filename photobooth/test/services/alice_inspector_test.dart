import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/alice_inspector.dart';
import 'package:photobooth/utils/app_runtime_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AliceInspector.resetForTests();
    AppRuntimeConfig.instance.applyFromSettings(null);
  });

  group('AliceInspector.resolveIsRequested', () {
    test('web is always off', () {
      expect(
        AliceInspector.resolveIsRequested(
          isWeb: true,
          showApiLogs: true,
          enableAliceDefine: 'true',
        ),
        isFalse,
      );
    });

    test('ENABLE_ALICE true wins over showApiLogs false', () {
      expect(
        AliceInspector.resolveIsRequested(
          isWeb: false,
          showApiLogs: false,
          enableAliceDefine: 'true',
        ),
        isTrue,
      );
    });

    test('native follows showApiLogs when dart-define unset', () {
      expect(
        AliceInspector.resolveIsRequested(
          isWeb: false,
          showApiLogs: true,
          enableAliceDefine: '',
        ),
        isTrue,
      );
      expect(
        AliceInspector.resolveIsRequested(
          isWeb: false,
          showApiLogs: false,
          enableAliceDefine: '',
        ),
        isFalse,
      );
    });
  });

  test('isRequested follows show_api_logs on native test VM', () {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: true),
    );
    expect(AliceInspector.isRequested, isTrue);
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: false),
    );
    expect(AliceInspector.isRequested, isFalse);
  });

  testWidgets('initialize creates instance when showApiLogs', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const SizedBox.shrink()),
    );
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: true),
    );
    AliceInspector.initialize(navKey);
    expect(AliceInspector.instance, isNotNull);
    expect(AliceInspector.navigatorKey, navKey);
    final interceptor = AliceInspector.dioInterceptor;
    expect(interceptor, isNotNull);
    expect(AliceInspector.dioInterceptor, same(interceptor));

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: false),
    );
    AliceInspector.syncWithRuntimeConfig();
    expect(AliceInspector.instance, isNull);
    expect(AliceInspector.dioInterceptor, isNull);
  });

  testWidgets('syncWithRuntimeConfig is a no-op without navigator', (
    tester,
  ) async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: true),
    );
    AliceInspector.syncWithRuntimeConfig();
    expect(AliceInspector.instance, isNull);
  });

  test('addHttpInspectorInterceptors attaches Alice proxy', () {
    final dio = Dio();
    addHttpInspectorInterceptors(dio);
    expect(
      dio.interceptors.whereType<AliceDioProxyInterceptor>(),
      isNotEmpty,
    );
  });

  test('dioInterceptor is null when Alice is off', () {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: false),
    );
    expect(AliceInspector.dioInterceptor, isNull);
  });

  test('AliceDioProxyInterceptor passes through when Alice is off', () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: false),
    );
    final dio = Dio();
    dio.interceptors.add(AliceDioProxyInterceptor());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, bool>>(
              requestOptions: options,
              statusCode: 200,
              data: const {'ok': true},
            ),
          );
        },
      ),
    );
    final res = await dio.get<Map<String, bool>>('http://example.com/ping');
    expect(res.statusCode, 200);
    expect(res.data, {'ok': true});
  });

  test('AliceDioProxyInterceptor onError passes through when Alice is off',
      () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: false),
    );
    final dio = Dio();
    dio.interceptors.add(AliceDioProxyInterceptor());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
    expect(
      () => dio.get<void>('http://example.com/fail'),
      throwsA(isA<DioException>()),
    );
  });

  test('AliceDioProxyInterceptor passes through when instance is null', () async {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showApiLogs: true),
    );
    AliceInspector.resetForTests();
    expect(AliceInspector.isRequested, isTrue);
    expect(AliceInspector.instance, isNull);

    final dio = Dio();
    dio.interceptors.add(AliceDioProxyInterceptor());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: 'ok',
            ),
          );
        },
      ),
    );
    final res = await dio.get<String>('http://example.com/ping');
    expect(res.data, 'ok');
  });
}
