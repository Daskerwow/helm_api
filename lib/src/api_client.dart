import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_request.dart';
import 'api_result.dart';

/// Контракт клиента. Интерфейс, а не конкретный класс — специально ради
/// тестируемости: в тестах приложения можно написать
/// `class MockApiClient extends Mock implements ApiClient {}`. С `final
/// class` (как было раньше) это не скомпилировалось бы за пределами
/// библиотеки.
///
/// Единственная реализация — [DioApiClient]. Место вызова не меняется:
/// `ApiClient(dio)` — обычный фабричный конструктор, который создаёт
/// [DioApiClient] под капотом.
///
/// ```dart
/// final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'));
/// dio.interceptors.add(LogInterceptor());     // логи — штатный Dio
/// dio.interceptors.add(MyAuthInterceptor());  // авторизация — штатный Dio
///
/// final ApiClient api = ApiClient(dio); // тип — интерфейс, значение — DioApiClient
///
/// final product = await api.execute(GetProduct(42));         // бросает ApiException
/// final result  = await api.tryExecute(GetProduct(42));       // ApiResult<Product>
/// final orNull  = await api.executeOrNull(GetProduct(42));    // null при 404
/// ```
abstract interface class ApiClient {
  const factory ApiClient(Dio dio) = DioApiClient;

  /// Выполняет запрос. Бросает [ApiException] при ошибке.
  ///
  /// [onSendProgress]/[onReceiveProgress] — для аплоада/загрузки больших
  /// файлов (см. `FormData`/`MultipartFile` в [ApiRequest.buildBody]).
  Future<Res> execute<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  });

  /// Выполняет запрос. Возвращает [ApiResult] вместо исключений.
  Future<ApiResult<Res>> tryExecute<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  });

  /// Выполняет запрос. Возвращает `null` при 404, бросает при остальных ошибках.
  Future<Res?> executeOrNull<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  });
}

// ─── DioApiClient ───────────────────────────────────────────────────────────

/// Единственная продакшн-реализация [ApiClient]. Тонкая обёртка над [Dio] —
/// никакой собственной абстракции транспорта: `baseUrl`, таймауты,
/// интерсепторы (логи, авторизация, ретраи) настраиваются на самом [Dio]
/// как обычно.
///
/// Если нужен прямой доступ к Dio в обход [ApiClient] (редкий, но иногда
/// нужный escape hatch) — держите поле `dio` у себя рядом с созданием
/// клиента, а не тащите его через интерфейс: `final dio = Dio(...); final
/// api = ApiClient(dio);` — `dio` всё ещё у вас под рукой.
final class const DioApiClient(final Dio dio) implements ApiClient {
  @override
  Future<Res> execute<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final response = await dio.request<Object?>(
        request.path,
        data: await request.buildBody(),
        queryParameters: request.queryParameters,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          method: request.method,
          headers: request.headers,
          extra: request.extra,
          responseType: request.responseType,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
        ),
      );

      try {
        return request.decode(response);
      } on ApiException {
        rethrow;
      } catch (e, st) {
        throw ParseException(
          'Ошибка декодирования ${request.tag}: $e',
          cause: e,
          stackTrace: st,
        );
      }
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ApiResult<Res>> tryExecute<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) => guardApi(
    () => execute(
      request,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  @override
  Future<Res?> executeOrNull<Res>(
    ApiRequest<Res> request, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      return await execute(
        request,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on HttpException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }
}
