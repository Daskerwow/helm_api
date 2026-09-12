import 'api_exception.dart';

/// Non-throwing outcome of an API operation.
sealed class const ApiResult<T>() {
  bool get isSuccess => this is ApiSuccess<T>;
  bool get isFailure => this is ApiFailure<T>;

  R when<R>({
    required R Function(T value) success,
    required R Function(ApiException error) failure,
  }) => switch (this) {
    ApiSuccess(:final value) => success(value),
    ApiFailure(:final error) => failure(error),
  };
}

/// Successful [ApiResult].
final class const ApiSuccess<T>(final T value) extends ApiResult<T>;

/// Failed [ApiResult].
final class const ApiFailure<T>(final ApiException error) extends ApiResult<T>;

/// Executes [operation] and turns a thrown API failure into [ApiResult].
Future<ApiResult<T>> guardApi<T>(Future<T> Function() operation) async {
  try {
    return ApiSuccess(await operation());
  } on ApiException catch (error) {
    return ApiFailure(error);
  } on Object catch (error, stackTrace) {
    return ApiFailure(
      ApiUnknownException(
        'An unexpected API error occurred.',
        cause: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
