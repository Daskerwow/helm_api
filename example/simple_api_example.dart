import 'package:dio/dio.dart';
import 'package:helm_api/helm_api.dart';

// ─── Модель ─────────────────────────────────────────────────────────────────

final class Product {
  const Product({required this.id, required this.title});
  final int id;
  final String title;

  factory Product.fromJson(Map<String, Object?> json) =>
      Product(id: json['id'] as int, title: json['title'] as String);

  Map<String, Object?> toJson() => {'title': title};

  @override
  String toString() => 'Product(#$id, $title)';
}

// ─── Запросы ────────────────────────────────────────────────────────────────

final class GetProduct extends JsonObjectRequest<Product> {
  const GetProduct(this.id);
  final int id;

  @override
  String get path => '/products/$id';

  @override
  Product decodeObject(Map<String, Object?> json) => Product.fromJson(json);
}

final class GetProducts extends PageRequest<Product> {
  const GetProducts(super.params);

  @override
  String get path => '/products';

  @override
  Product decodeItem(Map<String, Object?> json) => Product.fromJson(json);
}

final class CreateProduct extends JsonObjectRequest<Product> {
  const CreateProduct(this.title);
  final String title;

  @override
  String get path => '/products';

  @override
  String get method => 'POST';

  @override
  Future<Object?> buildBody() async => {'title': title};

  @override
  Product decodeObject(Map<String, Object?> json) => Product.fromJson(json);
}

// ─── Репозиторий ────────────────────────────────────────────────────────────

/// `ApiRepository` больше нет — `ApiClient` сам по себе достаточно тонкий,
/// репозиторий просто хранит его полем.
final class ProductRepository {
  const ProductRepository(this._api);
  final ApiClient _api;

  Future<ApiResult<Product>> find(int id) => _api.tryExecute(GetProduct(id));

  Future<Product> create(String title) => _api.execute(CreateProduct(title));

  Paginator<Product> paginator() =>
      Paginator<Product>(api: _api, requestFactory: GetProducts.new);
}

// ─── Сборка клиента и использование ────────────────────────────────────────

Future<void> main() async {
  // Обычный Dio — настраивается штатно, никакой обёртки над транспортом.
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
    ..options.headers['X-App-Version'] = '1.0.0'
    ..interceptors.add(LogInterceptor()); // логи — штатный Dio

  final api = ApiClient(dio);
  final repo = ProductRepository(api);

  // Вариант 1: бросает ApiException при ошибке
  final product = await api.execute(GetProduct(1));
  print(product);

  // Вариант 2: ApiResult — без исключений
  final result = await repo.find(1);
  result.when(
    success: (p) => print('OK: $p'),
    failure: (e) => print('Ошибка: ${e.message}'),
  );

  // Вариант 3: пагинация
  final paginator = repo.paginator();
  paginator.stream.listen((state) {
    print('Загружено: ${state.items.length}, статус: ${state.status}');
  });
  await paginator.loadFirst();
  await paginator.loadMore();
  paginator.dispose();

  // Создание ресурса
  final created = await repo.create('Новый товар');
  print('Создано: $created');
}
