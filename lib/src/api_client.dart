import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_page.dart';
import 'api_response.dart';
import 'api_result.dart';

/// Decodes a successful raw response when JSON convenience methods are not
/// sufficient, for example for bytes, headers or an empty `204` response.
typedef ApiDecoder<T> = T Function(ApiResponse response);

/// Decodes one JSON object into an application model.
typedef JsonObjectDecoder<T> = T Function(Map<String, Object?> json);

/// A small typed facade over [Dio].
///
/// Dio remains responsible for base URL, authentication, interceptors,
/// retries, upload/download transport and custom adapters. This class only
/// centralizes decoding and provides a consistent error/result contract.
final class const ApiClient(
  /// The underlying Dio instance for standard Dio configuration and escape
  /// hatches not represented by this intentionally small API.
  final Dio dio,
) {
  /// Executes an arbitrary request and throws a typed [ApiException] on
  /// transport or decoding failure.
  Future<T> request<T>(
    String path, {
    required String method,
    required ApiDecoder<T> decode,
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        options: (options ?? Options()).copyWith(method: method),
      );
      try {
        return decode(ApiResponse(response));
      } on ApiException {
        rethrow;
      } on Object catch (error, stackTrace) {
        throw ApiDecodingException(
          'Could not decode the response for $method $path.',
          cause: error,
          stackTrace: stackTrace,
        );
      }
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Non-throwing form of [request].
  Future<ApiResult<T>> tryRequest<T>(
    String path, {
    required String method,
    required ApiDecoder<T> decode,
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => guardApi(
    () => request(
      path,
      method: method,
      decode: decode,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  /// GET a JSON object and decode it with [decode].
  Future<T> getJson<T>(
    String path,
    JsonObjectDecoder<T> decode, {
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request(
    path,
    method: 'GET',
    decode: (response) => decode(response.jsonObject()),
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// GET a JSON array and decode each item with [decode].
  Future<List<T>> getJsonList<T>(
    String path,
    JsonObjectDecoder<T> decode, {
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request(
    path,
    method: 'GET',
    decode: (response) => response
        .jsonList()
        .map((item) {
          if (item is! Map) {
            throw ApiDecodingException(
              'Expected every JSON array item to be an object.',
            );
          }
          return decode(Map<String, Object?>.from(item));
        })
        .toList(growable: false),
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// POST JSON-compatible [data] and decode a JSON object response.
  Future<T> postJson<T>(
    String path,
    JsonObjectDecoder<T> decode, {
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => _sendJson(
    path,
    method: 'POST',
    decode: decode,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );

  /// PUT JSON-compatible [data] and decode a JSON object response.
  Future<T> putJson<T>(
    String path,
    JsonObjectDecoder<T> decode, {
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => _sendJson(
    path,
    method: 'PUT',
    decode: decode,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );

  /// PATCH JSON-compatible [data] and decode a JSON object response.
  Future<T> patchJson<T>(
    String path,
    JsonObjectDecoder<T> decode, {
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => _sendJson(
    path,
    method: 'PATCH',
    decode: decode,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );

  /// DELETE a resource whose successful response has no body.
  Future<void> delete(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => request(
    path,
    method: 'DELETE',
    decode: (_) {},
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// GET a conventional JSON page (`data` plus optional `meta`).
  Future<ApiPage<T>> getPage<T>(
    String path, {
    required JsonObjectDecoder<T> decodeItem,
    PageParams params = const PageParams(),
    Map<String, Object?>? queryParameters,
    String pageKey = 'page',
    String limitKey = 'limit',
    String itemsKey = 'data',
    String metaKey = 'meta',
    Options? options,
    CancelToken? cancelToken,
  }) => request(
    path,
    method: 'GET',
    decode: (response) => ApiPage.fromJson(
      response.data,
      params: params,
      decodeItem: decodeItem,
      itemsKey: itemsKey,
      metaKey: metaKey,
    ),
    queryParameters: {
      ...?queryParameters,
      ...params.toQueryParameters(pageKey: pageKey, limitKey: limitKey),
    },
    options: options,
    cancelToken: cancelToken,
  );

  Future<T> _sendJson<T>(
    String path, {
    required String method,
    required JsonObjectDecoder<T> decode,
    Object? data,
    Map<String, Object?>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => request(
    path,
    method: method,
    decode: (response) => decode(response.jsonObject()),
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
    onReceiveProgress: onReceiveProgress,
  );
}
