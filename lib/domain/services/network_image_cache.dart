import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../ports/file_system_port.dart';
import '../ports/image_fetcher_port.dart';

/// Persistent on-device cache of HTTPS-fetched image bytes (spec-004
/// Milestone B). Keyed by SHA-256 of the URL. Cache layout mirrors
/// [MermaidCache]: `<cacheDir>/<sha256>.<ext>` where `<ext>` is the
/// sanitized extension from the URL path (alphanumeric, ≤ 5 chars) or
/// `bin` if absent.
///
/// Invariants:
///   * Cache hit short-circuits the fetcher.
///   * Concurrent calls for the same URL share one in-flight future
///     (prevents the same WebView/OkHttp pool race spec-002 Mermaid
///     deferred — see `docs/Issues.md` "MermaidView spawns duplicate
///     WebViews").
///   * Fetcher failures throw [NetworkImageFetchFailed] and leave the
///     cache untouched, so a subsequent call retries cleanly.
///
/// Not thread-safe across isolates — the in-flight map is per-instance,
/// so the binding `Provider` must be non-`autoDispose` or the memo
/// disappears on the next screen mount.
class NetworkImageCache {
  /// Synchronous-dir constructor, used by tests that already know the
  /// cache root.
  NetworkImageCache({
    required FileSystemPort fs,
    required ImageFetcher fetch,
    required String cacheDir,
  })  : _fs = fs,
        _fetch = fetch,
        _resolveDir = (() async => cacheDir);

  /// Lazy-dir constructor for the production wiring path: the cache
  /// directory under app docs is resolved on the first call to
  /// [resolve] and memoized. Callers (e.g. the bootstrap provider)
  /// avoid having to `await` an async path before constructing the
  /// cache, which would force every consumer to thread a Future.
  NetworkImageCache.lazyDir({
    required FileSystemPort fs,
    required ImageFetcher fetch,
    required Future<String> Function() resolveDir,
  })  : _fs = fs,
        _fetch = fetch,
        _resolveDir = resolveDir;

  final FileSystemPort _fs;
  final ImageFetcher _fetch;
  final Future<String> Function() _resolveDir;

  String? _cachedDir;
  final Map<String, Future<String>> _inFlight = {};

  /// Returns the absolute path of the cached image bytes for [url],
  /// fetching + writing if the cache is cold. Throws
  /// [NetworkImageFetchFailed] when the fetcher errors.
  Future<String> resolve(Uri url) {
    final key = _keyFor(url);

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = _resolveUncached(url, key).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<String> _resolveUncached(Uri url, String key) async {
    final dir = _cachedDir ??= await _resolveDir();
    final path = '$dir/$key.${_sanitizedExtension(url)}';

    if (await _fs.exists(path)) return path;

    final Uint8List bytes;
    try {
      bytes = await _fetch.fetch(url);
    } catch (cause) {
      throw NetworkImageFetchFailed(url, cause);
    }

    await _fs.writeBytes(path, bytes);
    return path;
  }

  /// Deterministic SHA-256 key for [url].
  static String _keyFor(Uri url) {
    final digest = sha256.convert(utf8.encode(url.toString()));
    return digest.toString();
  }

  /// Pulls the lowercased extension from the URL path's last segment.
  /// Returns `'bin'` when the segment has no `.`, when the trailing
  /// component contains slashes (path traversal attempts like
  /// `/y.png/../etc`), or when the extension contains non-alphanumeric
  /// characters or is longer than 5 chars. Sanitization is defensive:
  /// the SHA is the cache key, the extension is cosmetic — but we still
  /// don't write user-controlled junk into a filename.
  static String _sanitizedExtension(Uri url) {
    final segments = url.pathSegments;
    if (segments.isEmpty) return 'bin';
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    if (dot < 0 || dot == last.length - 1) return 'bin';
    final raw = last.substring(dot + 1).toLowerCase();
    if (raw.isEmpty || raw.length > 5) return 'bin';
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(raw)) return 'bin';
    return raw;
  }
}

/// Typed failure thrown by [NetworkImageCache.resolve] when the fetcher
/// errors. The UI layer maps this to a "fetch failed" card showing only
/// [Uri.host] of [url] (never the full URL) per spec-004 §8b vibesec.
class NetworkImageFetchFailed implements Exception {
  const NetworkImageFetchFailed(this.url, this.cause);
  final Uri url;
  final Object cause;

  @override
  String toString() =>
      'NetworkImageFetchFailed(${url.host}${url.path}, cause: $cause)';
}
