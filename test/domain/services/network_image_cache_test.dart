import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/ports/image_fetcher_port.dart';
import 'package:gitmdscribe/domain/services/network_image_cache.dart';

class _CountingFetcher implements ImageFetcher {
  _CountingFetcher(this._bytes);
  final Uint8List _bytes;
  int calls = 0;

  @override
  Future<Uint8List> fetch(Uri url) async {
    calls += 1;
    return _bytes;
  }
}

class _ThrowingFetcher implements ImageFetcher {
  @override
  Future<Uint8List> fetch(Uri url) async {
    throw const _Boom();
  }
}

class _Boom implements Exception {
  const _Boom();
}

class _GatedFetcher implements ImageFetcher {
  final Completer<Uint8List> _gate = Completer<Uint8List>();
  int calls = 0;

  void release(Uint8List bytes) => _gate.complete(bytes);

  @override
  Future<Uint8List> fetch(Uri url) async {
    calls += 1;
    return _gate.future;
  }
}

NetworkImageCache _build({
  required ImageFetcher fetch,
  FakeFileSystem? fs,
  String cacheDir = '/docs/image-cache',
}) {
  return NetworkImageCache(
    fs: fs ?? FakeFileSystem(),
    fetch: fetch,
    cacheDir: cacheDir,
  );
}

void main() {
  group('NetworkImageCache', () {
    test('first call to resolve fetches and writes to disk', () async {
      final fs = FakeFileSystem();
      final fetcher = _CountingFetcher(Uint8List.fromList([1, 2, 3]));
      final cache = _build(fetch: fetcher, fs: fs);

      final path = await cache.resolve(Uri.parse('https://x.test/y.png'));

      expect(fetcher.calls, 1);
      expect(path.startsWith('/docs/image-cache/'), isTrue);
      expect(path.endsWith('.png'), isTrue);
      expect(await fs.exists(path), isTrue);
      expect(await fs.readBytes(path), [1, 2, 3]);
    });

    test('second call with same URL hits cache and skips fetcher', () async {
      final fetcher = _CountingFetcher(Uint8List.fromList([9]));
      final cache = _build(fetch: fetcher);

      final url = Uri.parse('https://x.test/y.png');
      final p1 = await cache.resolve(url);
      final p2 = await cache.resolve(url);

      expect(fetcher.calls, 1, reason: 'second resolve must not refetch');
      expect(p1, p2);
    });

    test('concurrent calls for same URL share one in-flight future',
        () async {
      final fetcher = _GatedFetcher();
      final cache = _build(fetch: fetcher);
      final url = Uri.parse('https://x.test/y.png');

      final f1 = cache.resolve(url);
      final f2 = cache.resolve(url);
      // Both calls registered before the fetcher resolves.
      await Future<void>.delayed(Duration.zero);
      expect(fetcher.calls, 1, reason: 'must memoize in-flight future');

      fetcher.release(Uint8List.fromList([7]));
      final p1 = await f1;
      final p2 = await f2;
      expect(p1, p2);
    });

    test('fetcher throws -> NetworkImageFetchFailed; nothing written',
        () async {
      final fs = FakeFileSystem();
      final cache = _build(fetch: _ThrowingFetcher(), fs: fs);

      await expectLater(
        cache.resolve(Uri.parse('https://x.test/y.png')),
        throwsA(isA<NetworkImageFetchFailed>()),
      );
      // No file landed in the cache dir.
      // (listDir on a missing dir throws; that's fine — implies nothing wrote)
      final exists = await fs.exists('/docs/image-cache');
      expect(exists, isFalse,
          reason: 'failed fetches must not create cache files');
    });

    test('url without extension is cached as <sha>.bin', () async {
      final fs = FakeFileSystem();
      final fetcher = _CountingFetcher(Uint8List.fromList([1]));
      final cache = _build(fetch: fetcher, fs: fs);

      final path = await cache.resolve(Uri.parse('https://x.test/no-ext'));

      expect(path.endsWith('.bin'), isTrue);
    });

    test('url with junk extension falls back to .bin (vibesec sanitization)',
        () async {
      final fetcher = _CountingFetcher(Uint8List.fromList([1]));
      final cache = _build(fetch: fetcher);

      // Path-traversal-ish or symbol-laced extensions must not land
      // verbatim on disk — sanitizer drops them to .bin.
      final path = await cache.resolve(
        Uri.parse('https://x.test/y.png/../etc'),
      );
      expect(path.endsWith('.bin'), isTrue,
          reason: 'extension must be alphanumeric after the last dot');
    });

    test('after a failed fetch resolves once succeeds, second call hits cache',
        () async {
      // Regression: in-flight memo entry must clean up on failure so a
      // retry can succeed; then a third call hits the warm cache.
      final fs = FakeFileSystem();
      final attempts = <bool>[true, false]; // throw first, succeed second
      var i = 0;
      final fetcher = _ScriptedFetcher(() {
        final shouldThrow = attempts[i++];
        if (shouldThrow) throw const _Boom();
        return Uint8List.fromList([1, 2]);
      });
      final cache = _build(fetch: fetcher, fs: fs);
      final url = Uri.parse('https://x.test/y.png');

      await expectLater(cache.resolve(url),
          throwsA(isA<NetworkImageFetchFailed>()));

      // Retry — should hit the (still-empty) cache, fetch again,
      // succeed, write the file.
      final path = await cache.resolve(url);
      expect(await fs.exists(path), isTrue);

      // Third call — cache hit, no new fetch.
      final pathAgain = await cache.resolve(url);
      expect(pathAgain, path);
      expect(i, 2, reason: 'fetcher invoked exactly twice (1 fail + 1 ok)');
    });
  });
}

class _ScriptedFetcher implements ImageFetcher {
  _ScriptedFetcher(this._next);
  final Uint8List Function() _next;

  @override
  Future<Uint8List> fetch(Uri url) async => _next();
}
