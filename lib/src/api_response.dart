import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Typed view over a successful Dio response used by advanced decoders.
final class const ApiResponse(
  /// Escape hatch for headers, redirects, request options and other Dio data.
  final Response<Object?> raw,
) {
  Object? get data => raw.data;
  int? get statusCode => raw.statusCode;
  Headers get headers => raw.headers;

  /// Returns the body as a JSON object or throws [ApiDecodingException].
  Map<String, Object?> jsonObject() {
    final value = data;
    if (value is! Map) {
      throw ApiDecodingException(
        'Expected a JSON object, received ${value.runtimeType}.',
      );
    }
    try {
      return Map<String, Object?>.from(value);
    } on Object catch (error, stackTrace) {
      throw ApiDecodingException(
        'Expected a JSON object with string keys.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Returns the body as a JSON array or throws [ApiDecodingException].
  List<Object?> jsonList() {
    final value = data;
    if (value is! List) {
      throw ApiDecodingException(
        'Expected a JSON array, received ${value.runtimeType}.',
      );
    }
    return List<Object?>.from(value);
  }
}
