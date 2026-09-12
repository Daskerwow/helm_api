import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_request.dart';

// ─── PageParams ─────────────────────────────────────────────────────────────

/// Параметры постраничной пагинации.
///
/// ```dart
/// var params = const PageParams(page: 1, limit: 20);
/// while (true) {
///   final page = await api.execute(GetProducts(params));
///   render(page.items);
///   if (!page.hasNextPage) break;
///   params = page.nextParams!;
/// }
/// ```
final class const PageParams({final int page = 1, final int limit = 20}) {
  /// Значения передаются Dio как есть (int) — сериализует сам, стрингификация
  /// вручную не нужна.
  Map<String, Object?> toQueryParameters({
    String pageKey = 'page',
    String limitKey = 'limit',
  }) => {pageKey: page, limitKey: limit};

  @override
  String toString() => 'PageParams(page: $page, limit: $limit)';
}

// ─── PagedResult ────────────────────────────────────────────────────────────

/// Результат постраничной выборки.
final class const PagedResult<T>({
  required final List<T> items,
  required final int totalCount,
  required final int currentPage,
  required final int limit,
  final int? totalPages,
}) {
  bool get hasNextPage {
    if (totalPages != null) return currentPage < totalPages!;
    return items.length >= limit;
  }

  bool get hasPreviousPage => currentPage > 1;
  bool get isEmpty => items.isEmpty;

  PageParams? get nextParams =>
      hasNextPage ? PageParams(page: currentPage + 1, limit: limit) : null;

  PagedResult<R> mapItems<R>(R Function(T item) transform) => PagedResult(
    items: items.map(transform).toList(growable: false),
    totalCount: totalCount,
    currentPage: currentPage,
    limit: limit,
    totalPages: totalPages,
  );

  @override
  String toString() =>
      'Page($currentPage/${totalPages ?? '?'}, ${items.length}/$totalCount items)';
}

// ─── PageRequest ────────────────────────────────────────────────────────────

/// Запрос с постраничной пагинацией.
///
/// ```dart
/// final class GetProducts extends PageRequest<Product> {
///   const GetProducts(super.params);
///   @override String get path => '/products';
///   @override Product decodeItem(Map<String, Object?> json) => Product(json);
/// }
/// ```
abstract base class const PageRequest<Item>(final PageParams params)
    extends ApiRequest<PagedResult<Item>> {
  @override
  Map<String, Object?> get queryParameters => params.toQueryParameters();

  @override
  PagedResult<Item> decode(Response<Object?> response) {
    final data = response.data;
    if (data is! Map) {
      throw ParseException(
        'Ожидался JSON-объект, получено: ${data.runtimeType}',
      );
    }
    try {
      return decodePage(Map<String, Object?>.from(data));
    } catch (e, st) {
      throw ParseException(
        'Ошибка декодирования страницы $runtimeType: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// По умолчанию — плоский формат `{ data: [...], total, limit, ... }`.
  /// Для вложенного `{ data: [...], meta: {...} }` переопределите на
  /// `PaginationMeta.fromNestedJson(...)`.
  PagedResult<Item> decodePage(Map<String, Object?> json) =>
      PaginationMeta.fromFlatJson(json: json, decoder: decodeItem);

  Item decodeItem(Map<String, Object?> json);
}

// ─── PaginationMeta ─────────────────────────────────────────────────────────

/// Хелперы для парсинга метаданных пагинации из разных форматов ответа API.
abstract final class const PaginationMeta._() {
  /// Плоский ответ: `{ data: [...], total: 100, limit: 20 }`.
  static PagedResult<T> fromFlatJson<T>({
    required Map<String, Object?> json,
    required T Function(Map<String, Object?>) decoder,
    String dataKey = 'data',
    String totalKey = 'total',
    String limitKey = 'limit',
    String currentPageKey = 'current_page',
    String lastPageKey = 'last_page',
  }) {
    final rawList = json[dataKey] as List? ?? [];
    final items = rawList
        .whereType<Map>()
        .map((e) => decoder(Map<String, Object?>.from(e)))
        .toList(growable: false);

    return PagedResult(
      items: items,
      totalCount: _int(json[totalKey]) ?? items.length,
      currentPage: _int(json[currentPageKey]) ?? 1,
      limit: _int(json[limitKey]) ?? items.length,
      totalPages: _int(json[lastPageKey]),
    );
  }

  /// Вложенный ответ: `{ data: [...], meta: { total, ... } }`.
  static PagedResult<T> fromNestedJson<T>({
    required Map<String, Object?> json,
    required T Function(Map<String, Object?>) decoder,
    String dataKey = 'data',
    String metaKey = 'meta',
  }) {
    final meta = (json[metaKey] as Map?)?.cast<String, Object?>() ?? {};
    return fromFlatJson(
      json: {...json, ...meta},
      decoder: decoder,
      dataKey: dataKey,
    );
  }

  static int? _int(Object? v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);
}

// ─── Paginator ──────────────────────────────────────────────────────────────

enum PaginatorStatus { idle, loading, loadingMore, loaded, loadedAll, error }

/// Иммутабельное состояние контроллера пагинации.
final class PaginatorState<T> {
  const PaginatorState({
    required this.items,
    required this.status,
    this.error,
    this.currentPage = 0,
    this.totalCount,
  });

  const new initial()
    : items = const [],
      status = .idle,
      error = null,
      currentPage = 0,
      totalCount = null;

  final List<T> items;
  final PaginatorStatus status;
  final ApiException? error;
  final int currentPage;
  final int? totalCount;

  bool get isLoading => status == .loading;
  bool get isLoadingMore => status == .loadingMore;
  bool get isLoaded => status == .loaded || status == .loadedAll;
  bool get isLoadedAll => status == .loadedAll;
  bool get hasError => status == .error;
  bool get isEmpty => items.isEmpty;
  bool get canLoadMore => status == .loaded;

  PaginatorState<T> copyWith({
    List<T>? items,
    PaginatorStatus? status,
    ApiException? error,
    bool clearError = false,
    int? currentPage,
    int? totalCount,
  }) => PaginatorState(
    items: items ?? this.items,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    currentPage: currentPage ?? this.currentPage,
    totalCount: totalCount ?? this.totalCount,
  );
}

/// Контроллер бесконечного скролла для постраничной пагинации.
/// Без внешних зависимостей (кроме Dio, транзитивно через [ApiClient]) —
/// простой broadcast-стрим + кэш текущего состояния.
///
/// ```dart
/// final paginator = Paginator<Product>(
///   api: api,
///   requestFactory: (params) => GetProducts(params),
/// );
///
/// await paginator.loadFirst();
/// paginator.stream.listen((s) => setState(() => _state = s));
/// await paginator.loadMore();   // при скролле в конец
/// await paginator.refresh();    // pull-to-refresh
/// paginator.dispose();
/// ```
final class Paginator<T> {
  Paginator({required this.api, required this.requestFactory, this.limit = 20})
    : _state = const PaginatorState.initial();

  final ApiClient api;
  final PageRequest<T> Function(PageParams params) requestFactory;
  final int limit;

  final _ctrl = StreamController<PaginatorState<T>>.broadcast();
  PaginatorState<T> _state;
  bool _loading = false;
  bool _disposed = false;

  /// Текущее состояние (доступно синхронно, в т.ч. до первой подписки на [stream]).
  PaginatorState<T> get state => _state;
  Stream<PaginatorState<T>> get stream => _ctrl.stream;

  Future<void> loadFirst() async {
    if (_loading) return;
    _emit(
      _state.copyWith(
        items: [],
        status: .loading,
        currentPage: 0,
        clearError: true,
      ),
    );
    await _load(append: false);
  }

  Future<void> loadMore() async {
    if (_loading || !_state.canLoadMore) return;
    _emit(_state.copyWith(status: .loadingMore, clearError: true));
    await _load(append: true);
  }

  Future<void> refresh() => loadFirst();

  Future<void> retryLoad() async {
    if (!_state.hasError) return;
    if (_state.currentPage == 0) {
      await loadFirst();
      return;
    }
    if (_loading) return;
    _emit(_state.copyWith(status: .loadingMore, clearError: true));
    await _load(append: true);
  }

  void dispose() {
    _disposed = true;
    _ctrl.close();
  }

  Future<void> _load({required bool append}) async {
    _loading = true;
    final targetPage = append ? _state.currentPage + 1 : 1;
    try {
      final result = await api.execute(
        requestFactory(PageParams(page: targetPage, limit: limit)),
      );

      final newItems = append
          ? [..._state.items, ...result.items]
          : result.items;

      _emit(
        _state.copyWith(
          items: newItems,
          status: result.hasNextPage ? .loaded : .loadedAll,
          currentPage: targetPage,
          totalCount: result.totalCount,
          clearError: true,
        ),
      );
    } on ApiException catch (e) {
      _emit(_state.copyWith(status: .error, error: e));
    } finally {
      _loading = false;
    }
  }

  void _emit(PaginatorState<T> s) {
    _state = s;
    if (!_disposed) _ctrl.add(s);
  }
}
