# helm_api

`helm_api` is a compact, type-safe API layer on top of [Dio](https://pub.dev/packages/dio).
It does not replace Dio: configure base URL, authentication, logging, retries,
uploads and custom adapters with Dio's own mature API. `helm_api` adds a small
decoding, error and pagination contract for application code.

```yaml
dependencies:
  helm_api: ^0.1.0
```

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'));
dio.interceptors.add(AuthInterceptor());

final api = ApiClient(dio);
```

## JSON requests

```dart
final user = await api.getJson('/users/42', User.fromJson);

final users = await api.getJsonList('/users', User.fromJson);

final created = await api.postJson(
  '/orders',
  Order.fromJson,
  data: {'product_id': productId, 'quantity': 2},
);

await api.delete('/orders/$orderId');
```

`User.fromJson` receives `Map<String, Object?>`. Use `request` when the
endpoint returns bytes, plain text, headers, or a non-standard response:

```dart
final fileBytes = await api.request(
  '/reports/latest',
  method: 'GET',
  options: Options(responseType: ResponseType.bytes),
  decode: (response) => response.data! as List<int>,
);
```

Every throwing operation maps transport and decoding failures to a typed
`ApiException`: `ApiNetworkException`, `ApiHttpException`,
`ApiCancelledException` or `ApiDecodingException`.

For UI flows where failures are values rather than control flow, use
`tryRequest`:

```dart
final result = await api.tryRequest(
  '/profile',
  method: 'GET',
  decode: (response) => User.fromJson(response.jsonObject()),
);

result.when(
  success: (user) => showUser(user),
  failure: (error) => showError(error.message),
);
```

## Pagination

`getPage` supports the common shapes below:

```json
{ "data": [{ "id": 1 }], "meta": { "current_page": 1, "per_page": 20, "total": 42 } }
```

```dart
final page = await api.getPage(
  '/products',
  params: const PageParams(page: 1, limit: 20),
  decodeItem: Product.fromJson,
);

if (page.hasNextPage) {
  final next = await api.getPage(
    '/products',
    params: page.nextParams,
    decodeItem: Product.fromJson,
  );
}
```

For another field convention, set `itemsKey`, `metaKey`, `pageKey` and
`limitKey`, or use the general `request` method and construct `ApiPage` in a
custom decoder.

## Lifecycle

`ApiClient` does not own `Dio`; the composition root that created `Dio` closes
it when the application shuts down. This keeps ownership explicit and works
naturally with `helm_di`.
