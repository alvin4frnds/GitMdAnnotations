import 'dart:typed_data';

/// Outbound HTTPS fetch boundary. Domain-layer code never touches `dio`
/// or `dart:io HttpClient` directly; [NetworkImageCache] composes this
/// port and the `FileSystemPort` to satisfy `![](https://...)` markdown
/// references offline-first.
///
/// Implementations (`DioImageFetcher` in `lib/infra/net/`, fakes in
/// `test/`) are responsible for: timeouts (≤ 15 s receive), redirect
/// limits (≤ 3 hops), and stripping any auth / cookie headers — public
/// URLs only for v1 per spec-004 §4.
abstract class ImageFetcher {
  /// Returns the raw response bytes for [url], or throws.
  Future<Uint8List> fetch(Uri url);
}
