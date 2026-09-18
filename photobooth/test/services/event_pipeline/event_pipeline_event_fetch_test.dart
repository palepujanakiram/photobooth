import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_event_fetch.dart';

/// Manual fake by subclass-and-override, per the repo convention.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({this.statusCode = 200, this.body, this.throwOnSend = false});

  int statusCode;
  Object? body;
  bool throwOnSend;
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    if (throwOnSend) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    }
    return ResponseBody.fromString(
      body == null ? '' : _encode(body!),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static String _encode(Object value) => value.toString();

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late FakeAdapter adapter;
  late EventPipelineEventFetch fetch;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    adapter = FakeAdapter();
    dio.httpClientAdapter = adapter;
    fetch = EventPipelineEventFetch(dio: dio);
  });

  test('returns the raw body so pipeline flags can be read from it', () async {
    adapter.body = '{"id":"evt-1","code":"GALA-01","pipelineEnabled":true}';
    final body = await fetch('GALA-01');

    expect(body, isNotNull);
    expect(body!['id'], 'evt-1');
    expect(body['pipelineEnabled'], isTrue,
        reason: 'the field EventInfoModel drops is the point of this fetcher');
  });

  test('upper-cases and trims the code into the path', () async {
    adapter.body = '{"id":"evt-1"}';
    await fetch('  gala-01 ');
    expect(adapter.lastPath, '/api/event/by-code/GALA-01');
  });

  test('a blank code is not a request', () async {
    expect(await fetch('   '), isNull);
    expect(adapter.lastPath, isNull);
  });

  test('a 4xx is a failed sync rather than an exception', () async {
    adapter.statusCode = 404;
    adapter.body = '{"error":"no such event"}';
    expect(await fetch('GALA-01'), isNull);
  });

  test('a 5xx is a failed sync too', () async {
    adapter.statusCode = 503;
    adapter.body = '{}';
    expect(await fetch('GALA-01'), isNull);
  });

  test('an unreachable backend returns null, because a venue with no link is '
      'normal and not an error', () async {
    adapter.throwOnSend = true;
    expect(await fetch('GALA-01'), isNull);
  });

  test('a body that is not an object is ignored', () async {
    adapter.body = '["not", "an", "object"]';
    expect(await fetch('GALA-01'), isNull);
  });

  test('an empty body is ignored', () async {
    adapter.body = null;
    expect(await fetch('GALA-01'), isNull);
  });
}
