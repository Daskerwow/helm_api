import 'api_exception.dart';

/// Типизированный результат API-вызова: успех или ошибка.
///
/// ```dart
/// final result = await api.tryExecute(GetProduct(42));
/// switch (result) {
///   case ApiSuccess(data: final p): render(p);
///   case ApiFailure(error: final e): showError(e.message);
/// }
/// ```
sealed class const ApiResult<T>() {
  bool get isSuccess => this is ApiSuccess<T>;
  bool get isFailure => this is ApiFailure<T>;

  /// Данные, либо бросает [ApiException].
  T get dataOrThrow => switch (this) {
    ApiSuccess(data: final d) => d,
    ApiFailure(error: final e) => throw e,
  };

  T? get dataOrNull => switch (this) {
    ApiSuccess(data: final d) => d,
    ApiFailure() => null,
  };

  T dataOrElse(T fallback) => switch (this) {
    ApiSuccess(data: final d) => d,
    ApiFailure() => fallback,
  };

  ApiException? get errorOrNull => switch (this) {
    ApiSuccess() => null,
    ApiFailure(error: final e) => e,
  };

  ApiResult<T> onSuccess(void Function(T data) action) {
    if (this case ApiSuccess(data: final d)) action(d);
    return this;
  }

  ApiResult<T> onFailure(void Function(ApiException error) action) {
    if (this case ApiFailure(error: final e)) action(e);
    return this;
  }

  R when<R>({
    required R Function(T data) success,
    required R Function(ApiException error) failure,
  }) => switch (this) {
    ApiSuccess(data: final d) => success(d),
    ApiFailure(error: final e) => failure(e),
  };

  ApiResult<R> map<R>(R Function(T data) transform) => switch (this) {
    ApiSuccess(data: final d) => ApiSuccess(transform(d)),
    ApiFailure(error: final e) => ApiFailure(e),
  };
}

final class const ApiSuccess<T>(final T data) extends ApiResult<T> {}

final class const ApiFailure<T>(final ApiException error)
    extends ApiResult<T> {}

/// Выполняет [call] и оборачивает результат в [ApiResult].
Future<ApiResult<T>> guardApi<T>(Future<T> Function() call) async {
  try {
    return ApiSuccess(await call());
  } on ApiException catch (e) {
    return ApiFailure(e);
  } catch (e, st) {
    return ApiFailure(UnknownException.wrap(e, st));
  }
}
