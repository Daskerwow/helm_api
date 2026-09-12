import 'package:dio/dio.dart';

/// Base type for failures produced while executing an API request.
sealed class const ApiException(
  /// Human-readable diagnostic suitable for logs or an error UI.
  final String message, {

  /// Original transport or decoder error for diagnostics.
  final Object? cause,

  /// Original stack trace when the failure has one.
  final StackTrace? stackTrace,
}) implements Exception {
  @override
  String toString() => '$runtimeType: $message';
}

/// The request did not receive an HTTP response: timeout, connection or DNS.
final class const ApiNetworkException(
  super.message, {
  super.cause,
  super.stackTrace,
}) extends ApiException;

/// The server responded with a non-success status code.
final class const ApiHttpException(
  super.message, {
  required final int statusCode,
  required final Object? body,
  required final Headers? headers,
  super.cause,
  super.stackTrace,
}) extends ApiException {
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500 && statusCode < 600;
}

/// The request was cancelled through Dio's [CancelToken].
final class const ApiCancelledException({
  String message = 'The request was cancelled.',
  Object? cause,
  StackTrace? stackTrace,
}) extends ApiException {
  this : super(message, cause: cause, stackTrace: stackTrace);
}

/// The endpoint replied successfully but its body did not match the decoder.
final class const ApiDecodingException(
  super.message, {
  super.cause,
  super.stackTrace,
}) extends ApiException;

/// An unexpected error escaped transport or application decoding.
final class ApiUnknownException extends ApiException {
  const ApiUnknownException(super.message, {super.cause, super.stackTrace});
}

/// Converts Dio's transport exception into the small public error hierarchy.
ApiException mapDioException(DioException error) {
  final response = error.response;
  if (response != null) {
    final statusCode = response.statusCode ?? 0;
    return ApiHttpException(
      _httpMessage(statusCode),
      statusCode: statusCode,
      body: response.data,
      headers: response.headers,
      cause: error,
      stackTrace: error.stackTrace,
    );
  }

  return switch (error.type) {
    .cancel => ApiCancelledException(
      message: error.message ?? 'The request was cancelled.',
      cause: error,
      stackTrace: error.stackTrace,
    ),
    .connectionTimeout ||
    .sendTimeout ||
    .receiveTimeout => ApiNetworkException(
      'The request timed out.',
      cause: error,
      stackTrace: error.stackTrace,
    ),
    _ => ApiNetworkException(
      error.message ?? 'A network error occurred.',
      cause: error,
      stackTrace: error.stackTrace,
    ),
  };
}

String _httpMessage(int statusCode) => switch (statusCode) {
  400 => 'The request is invalid.',
  401 => 'Authentication is required.',
  403 => 'Access is forbidden.',
  404 => 'The requested resource was not found.',
  409 => 'The request conflicts with current server state.',
  422 => 'The request failed validation.',
  429 => 'Too many requests.',
  >= 500 && < 600 => 'The server failed to process the request.',
  _ => 'The server returned HTTP $statusCode.',
};
