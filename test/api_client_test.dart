import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:helm_api/helm_api.dart';
import 'package:test/test.dart';

void main() {
  group('ApiClient JSON shortcuts', () {
    test('decodes an object and forwards query parameters', () async {
      final client = _client((options) {
        expect(options.method, 'GET');
        expect(options.path, '/users/7');
        expect(options.queryParameters, {'include': 'roles'});
        return _json({'id': 7, 'name': 'Ada'});
      });

      final user = await client.getJson(
        '/users/7',
        _User.fromJson,
        queryParameters: const {'include': 'roles'},
      );

      expect(user, const _User(7, 'Ada'));
    });

    test('sends JSON-compatible data through Dio', () async {
      final client = _client((options) {
        expect(options.method, 'POST');
        expect(options.data, {'name': 'Grace'});
        return _json({'id': 8, 'name': 'Grace'});
      });

      final user = await client.postJson(
        '/users',
        _User.fromJson,
        data: const {'name': 'Grace'},
      );

      expect(user, const _User(8, 'Grace'));
    });

    test('maps non-success responses to ApiHttpException', () async {
      final client = _client((_) => _json({'message': 'missing'}, status: 404));

      await expectLater(
        client.getJson('/users/404', _User.fromJson),
        throwsA(
          isA<ApiHttpException>()
              .having((error) => error.statusCode, 'status code', 404)
              .having((error) => error.isNotFound, 'not found', isTrue),
        ),
      );
    });

    test('returns a failure result without throwing', () async {
      final client = _client((_) => _json({}, status: 503));

      final result = await client.tryRequest(
        '/health',
        method: 'GET',
        decode: (response) => response.jsonObject(),
      );

      expect(result, isA<ApiFailure<Map<String, Object?>>>());
      final failure = result as ApiFailure<Map<String, Object?>>;
      expect(failure.error, isA<ApiHttpException>());
    });

    test('reports invalid JSON shapes as decoding failures', () async {
      final client = _client((_) => _json(['not', 'an', 'object']));

      await expectLater(
        client.getJson('/users/1', _User.fromJson),
        throwsA(isA<ApiDecodingException>()),
      );
    });
  });

  group('pagination', () {
    test('decodes nested metadata and computes the next page', () async {
      final client = _client((options) {
        expect(options.queryParameters, {'page': 2, 'limit': 2});
        return _json({
          'data': [
            {'id': 3, 'name': 'Ada'},
            {'id': 4, 'name': 'Grace'},
          ],
          'meta': {'current_page': 2, 'per_page': 2, 'total': 5},
        });
      });

      final page = await client.getPage(
        '/users',
        params: const PageParams(page: 2, limit: 2),
        decodeItem: _User.fromJson,
      );

      expect(page.items, [const _User(3, 'Ada'), const _User(4, 'Grace')]);
      expect(page.totalCount, 5);
      expect(page.hasNextPage, isTrue);
      expect(page.nextParams.page, 3);
    });
  });
}

ApiClient _client(FutureOr<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = _Adapter(handler);
  return ApiClient(dio);
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final class _Adapter implements HttpClientAdapter {
  _Adapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => _handler(options);
}

final class _User {
  const _User(this.id, this.name);

  factory _User.fromJson(Map<String, Object?> json) =>
      _User(json['id']! as int, json['name']! as String);

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _User && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
