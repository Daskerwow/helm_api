import 'package:dio/dio.dart';

/// Единая иерархия ошибок API. Прямая обёртка над [DioException] — никакой
/// собственной абстракции транспорта, только маппинг в понятные типы для
/// catch-блоков в приложении.
///
/// ```
/// ApiException
/// ├── NetworkException   — нет сети, таймаут, DNS (произошло ДО ответа)
/// ├── HttpException      — non-2xx ответ сервера
/// ├── ParseException     — не удалось декодировать тело ответа
/// ├── CancelException    — запрос отменён (dio.CancelToken)
/// └── UnknownException   — непредвиденная ошибка
/// ```
sealed class const ApiException(
  final String message, {
  final Object? cause,

  /// Стек оригинального исключения — критично для диагностики в проде
  /// (Sentry/Crashlytics покажут точное место падения `decodeObject`,
  /// а не только `runtimeType` запроса).
  final StackTrace? stackTrace,
}) implements Exception {
  @override
  String toString() => '$runtimeType: $message';
}

// ─── NetworkException ───────────────────────────────────────────────────────

/// Нет сети, таймаут, DNS-ошибка — всё, что произошло ДО ответа сервера.
final class const NetworkException(
  super.message, {
  super.cause,
  super.stackTrace,
}) extends ApiException;

// ─── HttpException ──────────────────────────────────────────────────────────

/// Сервер ответил non-2xx статусом.
final class const HttpException(
  super.message, {
  required final int statusCode,
  required final Response<Object?> response,
  super.cause,
  super.stackTrace,
}) extends ApiException {
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isUnprocessable => statusCode == 422;
  bool get isTooManyRequests => statusCode == 429;

  /// Тело ответа как JSON-объект, либо `null`, если это не Map.
  Map<String, Object?>? get jsonBody {
    final data = response.data;
    return data is Map ? Map<String, Object?>.from(data) : null;
  }

  /// Сообщение сервера из полей `message` / `error` / `detail`.
  String? get serverMessage {
    final body = jsonBody;
    if (body == null) return null;
    return (body['message'] ?? body['error'] ?? body['detail'])?.toString();
  }

  factory fromResponse(Response<Object?> response, {StackTrace? stackTrace}) {
    const statusMessages = {
      400: 'Некорректный запрос',
      401: 'Не авторизован',
      403: 'Доступ запрещён',
      404: 'Ресурс не найден',
      409: 'Конфликт данных',
      422: 'Ошибка валидации',
      429: 'Слишком много запросов',
      500: 'Внутренняя ошибка сервера',
      502: 'Сервер недоступен',
      503: 'Сервис временно недоступен',
    };

    final statusCode = response.statusCode ?? 0;
    final data = response.data;
    final String message;
    if (data is Map) {
      message =
          (data['message'] ?? data['error'] ?? data['detail'])?.toString() ??
          statusMessages[statusCode] ??
          'HTTP $statusCode';
    } else {
      message = statusMessages[statusCode] ?? 'HTTP $statusCode';
    }

    return HttpException(
      message,
      statusCode: statusCode,
      response: response,
      stackTrace: stackTrace,
    );
  }
}

// ─── ParseException ─────────────────────────────────────────────────────────

/// Не удалось декодировать тело ответа в ожидаемую модель.
final class const ParseException(super.message, {super.cause, super.stackTrace})
    extends ApiException;

// ─── CancelException ────────────────────────────────────────────────────────

/// Запрос отменён через `dio.CancelToken`.
final class const CancelException([super.message = 'Запрос отменён'])
    extends ApiException;

// ─── UnknownException ───────────────────────────────────────────────────────

/// Непредвиденная ошибка — обёртка над неклассифицированным исключением.
final class const UnknownException(
  super.message, {
  super.cause,
  super.stackTrace,
}) extends ApiException {
  factory wrap(Object error, [StackTrace? stackTrace]) =>
      UnknownException(error.toString(), cause: error, stackTrace: stackTrace);
}

// ─── mapDioException ────────────────────────────────────────────────────────

/// Превращает [DioException] в типизированный [ApiException].
/// Стек берётся из самого `DioException.stackTrace` — Dio его сохраняет.
ApiException mapDioException(DioException e) {
  final response = e.response;
  if (response != null) {
    return HttpException.fromResponse(response, stackTrace: e.stackTrace);
  }

  /// DioExceptionType
  return switch (e.type) {
    .connectionTimeout || .sendTimeout || .receiveTimeout => NetworkException(
      'Таймаут запроса',
      cause: e,
      stackTrace: e.stackTrace,
    ),
    .cancel => const CancelException(),
    .connectionError => NetworkException(
      e.message ?? 'Ошибка соединения',
      cause: e,
      stackTrace: e.stackTrace,
    ),
    _ => NetworkException(
      e.message ?? 'Сетевая ошибка',
      cause: e,
      stackTrace: e.stackTrace,
    ),
  };
}
