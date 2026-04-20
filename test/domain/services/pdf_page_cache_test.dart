import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/domain/services/pdf_page_cache.dart';

/// Tests for [PdfPageCache]. The cache wraps any [PdfRasterPort], keying
/// on `(handleId, pageNumber, targetSize)`, promoting on access, and
/// evicting the oldest entry once capacity is exceeded. It never
/// re-calls the underlying port on a cache hit. See IMPLEMENTATION.md
/// §4.4 (lazy-load pages, LRU cache).

CanvasSize _size1() => CanvasSize(width: 800, height: 1200);
CanvasSize _size2() => CanvasSize(width: 400, height: 600);

void main() {
  group('PdfPageCache basics', () {
    test('open and close pass through to the port', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 2);
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      expect(handle.id, '/a.pdf');
      expect(handle.pageCount, 2);
      expect(port.openedPaths, ['/a.pdf']);
      await cache.close(handle);
      expect(port.closedHandleIds, ['/a.pdf']);
    });

    test('default capacity is 8', () {
      final cache = PdfPageCache(port: FakePdfRasterPort());
      expect(cache.capacity, 8);
    });

    test('custom capacity is honored', () {
      final cache = PdfPageCache(port: FakePdfRasterPort(), capacity: 3);
      expect(cache.capacity, 3);
    });

    test('capacity must be positive', () {
      expect(
        () => PdfPageCache(port: FakePdfRasterPort(), capacity: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PdfPageCache(port: FakePdfRasterPort(), capacity: -2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('size starts at 0 and reports hits', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 2);
      final cache = PdfPageCache(port: port, capacity: 4);
      final handle = await cache.open('/a.pdf');
      expect(cache.size, 0);
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(cache.size, 1);
      await cache.renderPage(
        handle: handle,
        pageNumber: 2,
        targetSize: _size1(),
      );
      expect(cache.size, 2);
    });
  });

  group('PdfPageCache hits and misses', () {
    test('a miss calls the port and caches the result', () async {
      final port = FakePdfRasterPort()
        ..register(
          path: '/a.pdf',
          pageCount: 2,
          pagePngs: {1: Uint8List.fromList([7, 8, 9])},
        );
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      final bytes = await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(bytes, Uint8List.fromList([7, 8, 9]));
      expect(port.renderCalls, hasLength(1));
    });

    test('a hit returns cached bytes without re-calling the port',
        () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(1));
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(1));
    });

    test('different targetSize is a distinct cache key', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size2(),
      );
      expect(port.renderCalls, hasLength(2));
      expect(cache.size, 2);
    });

    test('different handles do not share cache entries', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 1)
        ..register(path: '/b.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final h1 = await cache.open('/a.pdf');
      final h2 = await cache.open('/b.pdf');
      await cache.renderPage(
        handle: h1,
        pageNumber: 1,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: h2,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(2));
      expect(cache.size, 2);
    });
  });

  group('PdfPageCache LRU eviction', () {
    test('evicts the oldest entry once capacity is exceeded', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 4);
      final cache = PdfPageCache(port: port, capacity: 2);
      final handle = await cache.open('/a.pdf');
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: handle,
        pageNumber: 2,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: handle,
        pageNumber: 3,
        targetSize: _size1(),
      );
      // Page 1 should have been evicted; re-rendering it calls the port
      // a 4th time.
      expect(cache.size, 2);
      expect(port.renderCalls, hasLength(3));
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(4));
    });

    test('hit promotes entry so it survives the next eviction', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 4);
      final cache = PdfPageCache(port: port, capacity: 2);
      final handle = await cache.open('/a.pdf');
      // Fill with pages 1 and 2.
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: handle,
        pageNumber: 2,
        targetSize: _size1(),
      );
      // Touch page 1 — promotes it, so page 2 is now the oldest.
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(2)); // still no extra port call.
      // Add page 3; page 2 should be evicted, page 1 survives.
      await cache.renderPage(
        handle: handle,
        pageNumber: 3,
        targetSize: _size1(),
      );
      // Page 1 stays cached → no 4th port call.
      await cache.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(3));
      // Page 2 was evicted → re-rendering it re-calls the port.
      await cache.renderPage(
        handle: handle,
        pageNumber: 2,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(4));
    });
  });

  group('PdfPageCache close semantics', () {
    test('close evicts all entries keyed by that handle id', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 2)
        ..register(path: '/b.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final a = await cache.open('/a.pdf');
      final b = await cache.open('/b.pdf');
      await cache.renderPage(
        handle: a,
        pageNumber: 1,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: a,
        pageNumber: 2,
        targetSize: _size1(),
      );
      await cache.renderPage(
        handle: b,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(cache.size, 3);
      await cache.close(a);
      // Only the /b.pdf entry remains.
      expect(cache.size, 1);
      // Re-rendering a page from the closed handle's doc (after reopening)
      // re-calls the port since the cache dropped it.
      final reopened = await cache.open('/a.pdf');
      await cache.renderPage(
        handle: reopened,
        pageNumber: 1,
        targetSize: _size1(),
      );
      expect(port.renderCalls, hasLength(4));
    });

    test('close forwards to the underlying port', () async {
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      await cache.close(handle);
      expect(port.closedHandleIds, ['/a.pdf']);
    });

    test('close(handle) is idempotent (second call is a no-op)', () async {
      // The provider layer fires `ref.onDispose` blindly, so a handle may
      // be closed more than once as pdf screens come and go. The cache
      // must absorb repeated closes and NOT forward them to the port a
      // second time — double-closing a real `pdfx` document is a crash
      // hazard, and the port contract promises one-close-per-open.
      final port = FakePdfRasterPort()
        ..register(path: '/a.pdf', pageCount: 1);
      final cache = PdfPageCache(port: port);
      final handle = await cache.open('/a.pdf');
      await cache.close(handle);
      // A second close must not throw and must not re-forward to the port.
      await cache.close(handle);
      expect(port.closedHandleIds, hasLength(1));
      expect(port.closedHandleIds.single, '/a.pdf');
    });
  });
}
