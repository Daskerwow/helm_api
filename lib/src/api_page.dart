import 'api_exception.dart';

/// Parameters for common one-based page/limit API pagination.
final class const PageParams({final int page = 1, final int limit = 20}) {
  this : assert(page > 0), assert(limit > 0);

  PageParams get next => PageParams(page: page + 1, limit: limit);

  Map<String, Object?> toQueryParameters({
    String pageKey = 'page',
    String limitKey = 'limit',
  }) => {pageKey: page, limitKey: limit};
}

/// A decoded API page. It is immutable and does not own loading state.
final class ApiPage<T>({
  required List<T> items,
  required final PageParams params,
  final int? totalCount,
  final int? totalPages,
}) {
  this : items = List.unmodifiable(items);

  ///
  final List<T> items;

  /// Whether another request with [nextParams] is expected to contain items.
  bool get hasNextPage {
    if (totalPages != null) return params.page < totalPages!;
    if (totalCount != null) return params.page * params.limit < totalCount!;
    return items.length >= params.limit;
  }

  PageParams get nextParams => params.next;

  /// Decodes common `{data, meta}` and flat `{data, total, page, limit}` APIs.
  static ApiPage<T> fromJson<T>(
    Object? source, {
    required PageParams params,
    required T Function(Map<String, Object?> json) decodeItem,
    String itemsKey = 'data',
    String metaKey = 'meta',
  }) {
    final json = _jsonObject(source, 'page response');
    final rawItems = json[itemsKey];
    if (rawItems is! List) {
      throw ApiDecodingException('Expected "$itemsKey" to be a JSON array.');
    }

    try {
      final items = rawItems
          .map((item) {
            return decodeItem(_jsonObject(item, 'page item'));
          })
          .toList(growable: false);
      final meta = json[metaKey] is Map
          ? _jsonObject(json[metaKey], 'pagination metadata')
          : json;
      return ApiPage(
        items: items,
        params: PageParams(
          page: _int(meta['current_page'] ?? meta['page']) ?? params.page,
          limit: _int(meta['per_page'] ?? meta['limit']) ?? params.limit,
        ),
        totalCount: _int(meta['total'] ?? meta['total_count']),
        totalPages: _int(meta['last_page'] ?? meta['total_pages']),
      );
    } on ApiException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw ApiDecodingException(
        'Could not decode the page response.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Map<String, Object?> _jsonObject(Object? value, String subject) {
  if (value is! Map) {
    throw ApiDecodingException(
      'Expected $subject to be a JSON object, received ${value.runtimeType}.',
    );
  }
  try {
    return Map<String, Object?>.from(value);
  } on Object catch (error, stackTrace) {
    throw ApiDecodingException(
      'Expected $subject to have string keys.',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

int? _int(Object? value) => switch (value) {
  int() => value,
  String() => int.tryParse(value),
  _ => null,
};
