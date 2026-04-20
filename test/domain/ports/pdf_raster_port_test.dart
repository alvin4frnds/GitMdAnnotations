import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/pdf_raster_port.dart';

/// Contract tests for [PdfRasterPort] + [FakePdfRasterPort]. The real
/// `pdfx` adapter is exercised only by the integration test at
/// `integration_test/pdf_raster_test.dart`; these tests pin the pure-Dart
/// port behavior + the scripting affordances the fake promises to its
/// callers. See IMPLEMENTATION.md §4.4 (PDF renderer) and §5.3 (TDD).

CanvasSize _sampleSize() => CanvasSize(width: 800, height: 1200);

void main() {
  group('PdfError sealed types', () {
    test('PdfOpenError carries message and path', () {
      const err = PdfOpenError(message: 'bad magic', path: '/tmp/a.pdf');
      expect(err.message, 'bad magic');
      expect(err.path, '/tmp/a.pdf');
      expect(err, isA<PdfError>());
      expect(err, isA<Exception>());
    });

    test('PdfRenderError carries message and pageNumber', () {
      const err = PdfRenderError(message: 'render blew up', pageNumber: 3);
      expect(err.message, 'render blew up');
      expect(err.pageNumber, 3);
      expect(err, isA<PdfError>());
      expect(err, isA<Exception>());
    });

    test('kinds are distinct (switch over sealed type compiles)', () {
      final PdfError open = const PdfOpenError(message: 'x', path: '/a');
      final PdfError render =
          const PdfRenderError(message: 'y', pageNumber: 2);
      expect(openOrRender(open), 'open:/a:x');
      expect(openOrRender(render), 'render:2:y');
    });

    test('toString includes context', () {
      expect(
        const PdfOpenError(message: 'bad', path: '/a.pdf').toString(),
        contains('/a.pdf'),
      );
      expect(
        const PdfRenderError(message: 'bad', pageNumber: 3).toString(),
        contains('3'),
      );
    });
  });

  group('FakePdfRasterPort assignability', () {
    test('FakePdfRasterPort satisfies PdfRasterPort', () {
      final PdfRasterPort port = FakePdfRasterPort();
      expect(port, isA<PdfRasterPort>());
    });
  });

  group('FakePdfRasterPort.open', () {
    test('opening an unregistered path throws PdfOpenError with the path',
        () async {
      final fake = FakePdfRasterPort();
      await expectLater(
        fake.open('/tmp/nope.pdf'),
        throwsA(
          isA<PdfOpenError>()
              .having((e) => e.path, 'path', '/tmp/nope.pdf')
              .having((e) => e.message, 'message', contains('not registered')),
        ),
      );
    });

    test(
        'opening a registered path returns a handle whose id equals the path',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 2);
      final handle = await fake.open('/tmp/a.pdf');
      expect(handle.id, '/tmp/a.pdf');
      expect(handle.pageCount, 2);
    });

    test('scriptOpenError consumes exactly one open call then resets',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1)
        ..scriptOpenError('boom');
      await expectLater(
        fake.open('/tmp/a.pdf'),
        throwsA(isA<PdfOpenError>()
            .having((e) => e.message, 'message', 'boom')),
      );
      // Second call hits the default happy path again.
      final handle = await fake.open('/tmp/a.pdf');
      expect(handle.id, '/tmp/a.pdf');
    });

    test('openedPaths records every open attempt, including errors',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      await fake.open('/tmp/a.pdf');
      await fake.open('/tmp/a.pdf');
      // Unregistered path throws but is still logged.
      try {
        await fake.open('/tmp/missing.pdf');
      } on PdfOpenError {
        // expected
      }
      expect(fake.openedPaths, ['/tmp/a.pdf', '/tmp/a.pdf', '/tmp/missing.pdf']);
    });

    test('openedPaths returns a defensive copy', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      await fake.open('/tmp/a.pdf');
      final snapshot = fake.openedPaths;
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(fake.openedPaths, hasLength(1));
    });
  });

  group('FakePdfRasterPort.renderPage', () {
    test('renderPage outside 1..pageCount throws RangeError', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 2);
      final handle = await fake.open('/tmp/a.pdf');
      await expectLater(
        fake.renderPage(
          handle: handle,
          pageNumber: 0,
          targetSize: _sampleSize(),
        ),
        throwsRangeError,
      );
      await expectLater(
        fake.renderPage(
          handle: handle,
          pageNumber: 3,
          targetSize: _sampleSize(),
        ),
        throwsRangeError,
      );
    });

    test('renderPage returns registered bytes for that page when present',
        () async {
      final fake = FakePdfRasterPort()
        ..register(
          path: '/tmp/a.pdf',
          pageCount: 2,
          pagePngs: {
            1: Uint8List.fromList([1, 2, 3]),
            2: Uint8List.fromList([4, 5, 6]),
          },
        );
      final handle = await fake.open('/tmp/a.pdf');
      expect(
        await fake.renderPage(
          handle: handle,
          pageNumber: 1,
          targetSize: _sampleSize(),
        ),
        Uint8List.fromList([1, 2, 3]),
      );
      expect(
        await fake.renderPage(
          handle: handle,
          pageNumber: 2,
          targetSize: _sampleSize(),
        ),
        Uint8List.fromList([4, 5, 6]),
      );
    });

    test(
        'renderPage returns the 8-byte PNG signature default '
        'when no per-page override is registered', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      final handle = await fake.open('/tmp/a.pdf');
      final bytes = await fake.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _sampleSize(),
      );
      expect(
        bytes,
        Uint8List.fromList(
          const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        ),
      );
    });

    test('scriptRenderError consumes exactly one render call then resets',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1)
        ..scriptRenderError('render boom');
      final handle = await fake.open('/tmp/a.pdf');
      await expectLater(
        fake.renderPage(
          handle: handle,
          pageNumber: 1,
          targetSize: _sampleSize(),
        ),
        throwsA(isA<PdfRenderError>()
            .having((e) => e.message, 'message', 'render boom')
            .having((e) => e.pageNumber, 'pageNumber', 1)),
      );
      final bytes = await fake.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _sampleSize(),
      );
      expect(bytes, isNotEmpty);
    });

    test('renderCalls records handleId, pageNumber, and targetSize in order',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 2);
      final handle = await fake.open('/tmp/a.pdf');
      final s1 = CanvasSize(width: 100, height: 200);
      final s2 = CanvasSize(width: 300, height: 400);
      await fake.renderPage(handle: handle, pageNumber: 1, targetSize: s1);
      await fake.renderPage(handle: handle, pageNumber: 2, targetSize: s2);
      expect(fake.renderCalls, hasLength(2));
      expect(fake.renderCalls[0].handleId, '/tmp/a.pdf');
      expect(fake.renderCalls[0].pageNumber, 1);
      expect(fake.renderCalls[0].targetSize, s1);
      expect(fake.renderCalls[1].handleId, '/tmp/a.pdf');
      expect(fake.renderCalls[1].pageNumber, 2);
      expect(fake.renderCalls[1].targetSize, s2);
    });

    test('renderCalls returns a defensive copy', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      final handle = await fake.open('/tmp/a.pdf');
      await fake.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _sampleSize(),
      );
      final snapshot = fake.renderCalls;
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(fake.renderCalls, hasLength(1));
    });

    test('registered override bytes are defensively copied on read',
        () async {
      final mutable = Uint8List.fromList([1, 2, 3]);
      final fake = FakePdfRasterPort()
        ..register(
          path: '/tmp/a.pdf',
          pageCount: 1,
          pagePngs: {1: mutable},
        );
      final handle = await fake.open('/tmp/a.pdf');
      mutable[0] = 99;
      final bytes = await fake.renderPage(
        handle: handle,
        pageNumber: 1,
        targetSize: _sampleSize(),
      );
      expect(bytes, Uint8List.fromList([1, 2, 3]));
    });
  });

  group('FakePdfRasterPort.close', () {
    test('close of a registered handle is idempotent', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      final handle = await fake.open('/tmp/a.pdf');
      await fake.close(handle);
      await fake.close(handle); // no throw
      expect(fake.closedHandleIds, ['/tmp/a.pdf', '/tmp/a.pdf']);
    });

    test('closedHandleIds returns a defensive copy', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/tmp/a.pdf', pageCount: 1);
      final handle = await fake.open('/tmp/a.pdf');
      await fake.close(handle);
      final snapshot = fake.closedHandleIds;
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(fake.closedHandleIds, hasLength(1));
    });
  });
}

/// Helper that forces an exhaustive match on [PdfError] at compile time.
/// Used by the `kinds are distinct` test above to prove the sealed type
/// lets callers discriminate without a catch-all default.
String openOrRender(PdfError e) {
  return switch (e) {
    PdfOpenError(:final message, :final path) => 'open:$path:$message',
    PdfRenderError(:final message, :final pageNumber) =>
      'render:$pageNumber:$message',
  };
}
