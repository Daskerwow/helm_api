/// Тончайший типизированный слой поверх Dio: один класс на эндпоинт,
/// единая иерархия ошибок, управление пагинацией. Никакой собственной
/// абстракции транспорта — весь HTTP на самом Dio (baseUrl, таймауты,
/// интерсепторы логов/авторизации/ретраев — стандартными средствами Dio).
library;

export 'package:dio/dio.dart'
    show Dio, BaseOptions, Response, CancelToken, FormData, MultipartFile;

export 'src/api_client.dart';
export 'src/api_exception.dart';
export 'src/api_request.dart';
export 'src/api_result.dart';
export 'src/pagination.dart';
