import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/ports/image_fetcher_port.dart';

/// Production [ImageFetcher] backed by `dio`. Public-URL only:
/// emits no auth headers, no cookies. Caps redirects at 3 to defend
/// against open-redirect chains. 10 s send / 15 s receive timeouts so a
/// dead URL never freezes the markdown render.
///
/// Cleartext `http://` requests are subject to Android's network
/// security config — on `targetSdk ≥ 28` they fail at the platform
/// layer with `CleartextNotPermittedException`. Surface as a fetch
/// failure; do not relax the security config to allow cleartext.
class DioImageFetcher implements ImageFetcher {
  DioImageFetcher({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<Uint8List> fetch(Uri url) async {
    final resp = await _dio.get<List<int>>(
      url.toString(),
      options: Options(
        responseType: ResponseType.bytes,
        // Explicit empty headers — never inherit Dio defaults that
        // could carry an Authorization or Cookie set elsewhere in the
        // app.
        headers: const <String, dynamic>{},
        followRedirects: true,
        maxRedirects: 3,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw const _EmptyResponse();
    }
    return Uint8List.fromList(data);
  }
}

class _EmptyResponse implements Exception {
  const _EmptyResponse();
  @override
  String toString() => 'DioImageFetcher: empty response body';
}
