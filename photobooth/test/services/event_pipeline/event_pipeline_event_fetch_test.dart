import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_event_fetch.dart';
import 'package:photobooth/services/kiosk_manager.dart';

/// One canned response, keyed by exact request path (no query string).
class FakeRoute {
  const FakeRoute({this.statusCode = 200, this.body});
  final int statusCode;
  final Object? body;
}

/// Manual fake by subclass-and-override, per the repo convention.
///
/// Routes by path so a test can give the verify call and the settings call
/// different bodies; a path with no route falls back to [statusCode] / [body].
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({
    this.statusCode = 200,
    this.body,
    this.throwOnSend = false,
    this.routes = const {},
  });

  int statusCode;
  Object? body;
  bool throwOnSend;
  Map<String, FakeRoute> routes;
  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> requestedQueries = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    requestedQueries.add(options.queryParameters);
    if (throwOnSend) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    final route = routes[options.path];
    final code = route?.statusCode ?? statusCode;
    final b = routes.containsKey(options.path) ? route?.body : body;
    return ResponseBody.fromString(
      b == null ? '' : _encode(b),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static String _encode(Object value) => value.toString();

  @override
  void close({bool force = false}) {}
}

/// A kiosk with no code, so tests that do not care about it stay unaffected.
class _NoKioskManager implements KioskManager {
  const _NoKioskManager();
  @override
  Future<String?> getKioskCode() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by EventPipelineEventFetch tests');
}

void main() {
  late Dio dio;
  late FakeAdapter adapter;
  late EventPipelineEventFetch fetch;

  const verifyPath = '/api/event/by-code/GALA-01';
  const settingsPath = '/api/events/by-code/GALA-01/settings';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    adapter = FakeAdapter();
    dio.httpClientAdapter = adapter;
    fetch = EventPipelineEventFetch(dio: dio, kiosk: const _NoKioskManager());
  });

  test('merges the settings endpoint over the verify body', () async {
    adapter.routes = {
      verifyPath: const FakeRoute(
        body: '{"success":true,"event":{"id":"evt-1","themeIds":["t1","t2"],'
            '"frameIds":["f1"]}}',
      ),
      settingsPath: const FakeRoute(
        body: '{"aiEnabled":true,"themeId":"t2","frameEnabled":false,'
            '"frameId":"","autoPrint":true,"defaultCopies":2,'
            '"printSize":"s5x7","startsAt":null,"endsAt":null}',
      ),
    };

    final body = await fetch('gala-01');

    expect(body, isNotNull);
    // Verify-only field survives the merge.
    expect(body!['id'], 'evt-1');
    expect(body['themeIds'], ['t1', 't2']);
    // Settings fields land on the merged map, unwrapped.
    expect(body['aiEnabled'], isTrue);
    expect(body['themeId'], 't2');
    expect(body['autoPrint'], isTrue);
    expect(body['defaultCopies'], 2);
    expect(body['printSize'], 's5x7');
  });

  test('settings values win over any same-named verify field', () async {
    adapter.routes = {
      verifyPath: const FakeRoute(
        body: '{"event":{"id":"evt-1","printSize":"s4x6"}}',
      ),
      settingsPath: const FakeRoute(body: '{"printSize":"s6x8"}'),
    };

    final body = await fetch('GALA-01');
    expect(body!['printSize'], 's6x8');
  });

  test('a failed settings fetch still returns the verify-derived body',
      () async {
    adapter.routes = {
      verifyPath: const FakeRoute(body: '{"event":{"id":"evt-1"}}'),
      settingsPath: const FakeRoute(statusCode: 500, body: '{}'),
    };

    final body = await fetch('GALA-01');
    expect(body, isNotNull);
    expect(body!['id'], 'evt-1');
    expect(body.containsKey('aiEnabled'), isFalse);
  });

  test('a failed verify fetch aborts before the settings call', () async {
    adapter.routes = {
      verifyPath: const FakeRoute(statusCode: 404, body: '{"error":"no"}'),
    };

    expect(await fetch('GALA-01'), isNull);
    expect(adapter.requestedPaths, [verifyPath]);
  });

  test('requests both endpoints, upper-cased and trimmed into the path',
      () async {
    adapter.body = '{"event":{"id":"evt-1"}}';
    await fetch('  gala-01 ');
    expect(adapter.requestedPaths, [verifyPath, settingsPath]);
  });

  test('passes the kiosk code as a query parameter on the settings call',
      () async {
    adapter.body = '{"event":{"id":"evt-1"}}';
    fetch = EventPipelineEventFetch(
      dio: dio,
      kiosk: _FakeKioskManager('booth-9'),
    );

    await fetch('GALA-01');

    expect(adapter.requestedQueries.last['kioskCode'], 'BOOTH-9');
  });

  test('a body with no event wrapper is used as-is (test fixture shape)',
      () async {
    adapter.routes = {
      verifyPath: const FakeRoute(body: '{"id":"evt-1","pipelineEnabled":true}'),
      settingsPath: const FakeRoute(statusCode: 500),
    };
    final body = await fetch('GALA-01');
    expect(body!['id'], 'evt-1');
    expect(body['pipelineEnabled'], isTrue);
  });

  test('a blank code is not a request', () async {
    expect(await fetch('   '), isNull);
    expect(adapter.requestedPaths, isEmpty);
  });

  test('a 5xx on verify is a failed sync too', () async {
    adapter.statusCode = 503;
    adapter.body = '{}';
    expect(await fetch('GALA-01'), isNull);
  });

  test('an unreachable backend returns null, because a venue with no link is '
      'normal and not an error', () async {
    adapter.throwOnSend = true;
    expect(await fetch('GALA-01'), isNull);
  });

  test('a verify body that is not an object is ignored', () async {
    adapter.body = '["not", "an", "object"]';
    expect(await fetch('GALA-01'), isNull);
  });

  test('an empty verify body is ignored', () async {
    adapter.body = null;
    expect(await fetch('GALA-01'), isNull);
  });
}

class _FakeKioskManager implements KioskManager {
  _FakeKioskManager(this._code);
  final String _code;
  @override
  Future<String?> getKioskCode() async => _code;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by EventPipelineEventFetch tests');
}
