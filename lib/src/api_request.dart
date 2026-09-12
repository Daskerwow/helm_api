import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Типизированное описание API-запроса. Каждый эндпоинт — отдельный класс.
///
/// Работает напрямую поверх Dio: [decode] получает нативный `dio.Response`,
/// [buildBody] может вернуть что угодно, что понимает сам Dio — `Map`/`List`
/// (Dio сериализует в JSON сам), `FormData`, строку, байты.
///
/// ```dart
/// // GET /products/:id — метод по умолчанию 'GET', GetMethod не обязателен
/// final class GetProduct extends JsonObjectRequest<Product> {
///   const GetProduct(this.id);
///   final int id;
///
///   @override String get path => '/products/$id';
///   @override Product decodeObject(Map<String, Object?> json) => Product(json);
/// }
///
/// // POST /orders — `with PostMethod` вместо ручного `@override String get method`
/// final class CreateOrder extends JsonObjectRequest<Order> with PostMethod {
///   const CreateOrder(this.dto);
///   final CreateOrderDto dto;
///
///   @override String get path => '/orders';
///   @override Future<Object?> buildBody() async => dto.toJson();
///   @override Order decodeObject(Map<String, Object?> json) => Order(json);
/// }
///
/// // POST /orders/:id/photo (multipart) — FormData строится прямо из Dio,
/// // никакой собственной обёртки над файлами не нужно.
/// final class UploadPhoto extends JsonObjectRequest<Order> with PostMethod {
///   const UploadPhoto(this.orderId, this.filePath);
///   final int orderId;
///   final String filePath;
///
///   @override String get path => '/orders/$orderId/photo';
///   @override Future<Object?> buildBody() async => FormData.fromMap({
///     'photo': await MultipartFile.fromFile(filePath),
///   });
///   @override Order decodeObject(Map<String, Object?> json) => Order(json);
/// }
///
/// // DELETE /products/:id → 204 No Content
/// final class DeleteProduct extends VoidRequest with DeleteMethod {
///   const DeleteProduct(this.id);
///   final int id;
///
///   @override String get path => '/products/$id';
/// }
/// ```
abstract base class const ApiRequest<Res>() {
  /// Путь относительно `dio.options.baseUrl`, например: `/products/42`.
  ///
  /// Динамические сегменты пути (не int) экранируйте через
  /// [encodePathSegment] — путь не кодируется автоматически, и строка вроде
  /// `/search/some free text` или `/search/a?b=c` сломает роутинг или
  /// превратится в query-инъекцию.
  ///
  /// ```dart
  /// @override String get path => '/search/${encodePathSegment(query)}';
  /// ```
  String get path;

  String get method => 'GET';

  /// Query-параметры. Значения передаются Dio как есть — сериализует сам.
  Map<String, Object?> get queryParameters => const {};

  /// Заголовки, специфичные для запроса. Перекрывают дефолтные заголовки Dio.
  Map<String, Object?> get headers => const {};

  /// Метаданные запроса, доступные интерсепторам Dio через
  /// `RequestOptions.extra` — стандартный способ пометить конкретный запрос
  /// для своего интерсептора (например `{'skipAuth': true}`), не трогая
  /// саму библиотеку.
  Map<String, Object?> get extra => const {};

  /// Переопределяет тип ответа для конкретного запроса — например
  /// `ResponseType.bytes` для скачивания файла через тот же `execute()`.
  /// `null` — берётся из `BaseOptions` (по умолчанию `ResponseType.json`).
  ResponseType? get responseType => null;

  /// Таймауты на конкретный запрос — переопределяют `BaseOptions`, если
  /// какой-то эндпоинт заведомо медленнее/быстрее остальных. `null` —
  /// берётся из `BaseOptions`.
  Duration? get sendTimeout => null;
  Duration? get receiveTimeout => null;

  /// Тело запроса. `null` — тела нет (обычно для GET/HEAD/DELETE).
  Future<Object?> buildBody() async => null;

  /// Декодирует успешный ответ. Вызывается только для 2xx — на остальные
  /// статусы Dio сам бросает `DioException` ещё до вызова [decode].
  Res decode(Response<Object?> response);

  /// Тег для логирования/отладки. По умолчанию — имя класса.
  String get tag => runtimeType.toString();
}

/// Экранирует значение для безопасной подстановки в путь запроса.
///
/// ```dart
/// @override String get path => '/search/${encodePathSegment(freeTextQuery)}';
/// ```
String encodePathSegment(Object value) => Uri.encodeComponent('$value');

// ─── Method mixins ──────────────────────────────────────────────────────────

/// Готовые примеси для HTTP-метода — чтобы не писать
/// `@override String get method => 'POST';` руками на каждом запросе и не
/// опечататься в строке. Композиция вместо отдельной иерархии типов на
/// каждую комбинацию метод×формат ответа (это была бы `Get/Post/Put/Patch/
/// Delete` × `JsonObject/JsonList/Void/Raw` = 20 классов — обратно к
/// раздуванию, от которого библиотека и уходила).
///
/// ```dart
/// final class CreateOrder extends JsonObjectRequest<Order> with PostMethod {
///   const CreateOrder(this.dto);
///   final CreateOrderDto dto;
///   @override String get path => '/orders';
///   @override Future<Object?> buildBody() async => dto.toJson();
///   @override Order decodeObject(Map<String, Object?> json) => Order(json);
/// }
/// ```
///
/// [GetMethod] не обязателен — `'GET'` уже дефолт в [ApiRequest.method];
/// добавляйте, только если хочется явности рядом с остальными `with`.
base mixin GetMethod on ApiRequest<Object?> {
  @override
  String get method => 'GET';
}

base mixin PostMethod on ApiRequest<Object?> {
  @override
  String get method => 'POST';
}

base mixin PutMethod on ApiRequest<Object?> {
  @override
  String get method => 'PUT';
}

base mixin PatchMethod on ApiRequest<Object?> {
  @override
  String get method => 'PATCH';
}

base mixin DeleteMethod on ApiRequest<Object?> {
  @override
  String get method => 'DELETE';
}

base mixin HeadMethod on ApiRequest<Object?> {
  @override
  String get method => 'HEAD';
}

// ─── JsonObjectRequest ──────────────────────────────────────────────────────

/// Запрос, возвращающий один объект из JSON-объекта.
abstract base class const JsonObjectRequest<Res>() extends ApiRequest<Res> {
  @override
  Res decode(Response<Object?> response) {
    final data = response.data;
    if (data is! Map) {
      throw ParseException(
        'Ожидался JSON-объект, получено: ${data.runtimeType}',
      );
    }
    try {
      return decodeObject(Map<String, Object?>.from(data));
    } catch (e, st) {
      throw ParseException(
        'Ошибка декодирования $runtimeType: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  Res decodeObject(Map<String, Object?> json);
}

// ─── JsonListRequest ────────────────────────────────────────────────────────

/// Запрос, возвращающий список из JSON-массива.
abstract base class const JsonListRequest<Item>()
    extends ApiRequest<List<Item>> {
  @override
  List<Item> decode(Response<Object?> response) {
    final data = response.data;
    if (data is! List) {
      throw ParseException(
        'Ожидался JSON-массив, получено: ${data.runtimeType}',
      );
    }
    try {
      return [
        for (final item in data)
          if (item is Map) decodeItem(Map<String, Object?>.from(item)),
      ];
    } catch (e, st) {
      throw ParseException(
        'Ошибка декодирования списка $runtimeType: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  Item decodeItem(Map<String, Object?> json);
}

// ─── VoidRequest ────────────────────────────────────────────────────────────

/// Запрос без тела ответа (204 No Content или аналог).
abstract base class const VoidRequest() extends ApiRequest<void> {
  @override
  void decode(Response<Object?> response) {}
}

// ─── RawRequest ─────────────────────────────────────────────────────────────

/// Запрос с прямым доступом к `dio.Response`. Для нестандартных форматов —
/// бинарные файлы, XML, что угодно за пределами JSON.
abstract base class const RawRequest() extends ApiRequest<Response<Object?>> {
  @override
  Response<Object?> decode(Response<Object?> response) => response;
}
