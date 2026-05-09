import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/image_fetcher_port.dart';
import '../../domain/services/network_image_cache.dart';
import 'spec_providers.dart';

/// Bound at composition root in `bootstrap.dart`. Real mode wires
/// [DioImageFetcher]; mockup mode wires a fake that returns canned
/// bytes. Tests override directly.
final imageFetcherProvider = Provider<ImageFetcher>((ref) {
  throw UnimplementedError(
    'imageFetcherProvider must be overridden at composition root',
  );
});

/// Test seam: when non-null, [networkImageCacheProvider] uses this as
/// the cache directory instead of resolving via
/// [FileSystemPort.appDocsPath]. `bootstrap.dart` does not override it.
final imageCacheDirOverrideProvider = Provider<String?>((ref) => null);

/// On-device cache for HTTPS image fetches.
///
/// Non-`autoDispose` so the in-flight memoization map (which prevents
/// two `_NetworkImage` widgets from racing the same URL) survives
/// screen re-mount.
///
/// Constructed via [NetworkImageCache.lazyDir] so the async
/// `appDocsPath` lookup happens on the first call to `cache.resolve`,
/// not at provider build time. `_NetworkImage.initState` therefore
/// reads the provider synchronously and awaits a single Future for the
/// dir + fetch + write.
final networkImageCacheProvider = Provider<NetworkImageCache>((ref) {
  final fs = ref.read(fileSystemProvider);
  final fetch = ref.read(imageFetcherProvider);
  final override = ref.read(imageCacheDirOverrideProvider);
  if (override != null) {
    return NetworkImageCache(fs: fs, fetch: fetch, cacheDir: override);
  }
  return NetworkImageCache.lazyDir(
    fs: fs,
    fetch: fetch,
    resolveDir: () => fs.appDocsPath('image-cache'),
  );
});
