import 'package:dio/dio.dart';

import '../../domain/ports/auth_port.dart';
import 'github_oauth_adapter.dart';

/// Production [HttpTransport] backed by a single [Dio] instance. POSTs are
/// form-encoded (GitHub's /device/code and /access_token endpoints accept
/// `application/x-www-form-urlencoded` and return JSON when `Accept` asks).
/// Maps any [DioException] to [AuthNetworkFailure] so callers only ever see
/// domain-typed errors.
class DefaultHttpTransport implements HttpTransport {
  DefaultHttpTransport({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
              responseType: ResponseType.json,
            ));

  final Dio _dio;

  @override
  Future<HttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Map<String, dynamic> body = const {},
  }) =>
      _run(() => _dio.post<dynamic>(
            url,
            data: body,
            options: Options(
              headers: headers,
              contentType: Headers.formUrlEncodedContentType,
              validateStatus: (_) => true,
            ),
          ));

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) =>
      _run(() => _dio.get<dynamic>(
            url,
            options: Options(headers: headers, validateStatus: (_) => true),
          ));

  Future<HttpResponse> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      final body = data is Map<String, dynamic>
          ? data
          : data is Map
              ? data.map((k, v) => MapEntry(k.toString(), v))
              : const <String, dynamic>{};
      return HttpResponse(res.statusCode ?? 0, body);
    } on DioException catch (e) {
      throw AuthNetworkFailure(e);
    }
  }
}
