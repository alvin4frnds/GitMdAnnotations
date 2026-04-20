import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/pdf_providers.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/domain/services/pdf_page_cache.dart';

void main() {
  group('pdfRasterPortProvider', () {
    test('throws UnimplementedError when not overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(pdfRasterPortProvider),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('override returns the supplied port', () {
      final fake = FakePdfRasterPort();
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      expect(container.read(pdfRasterPortProvider), same(fake));
    });
  });

  group('pdfPageCacheProvider', () {
    test('wraps the port with default capacity 8', () {
      final fake = FakePdfRasterPort();
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      final cache = container.read(pdfPageCacheProvider);
      expect(cache, isA<PdfPageCache>());
      expect(cache.capacity, 8);
    });
  });

  group('pdfDocumentNotifierProvider', () {
    test('opens a document via the cache and resolves to a handle', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/docs/one.pdf', pageCount: 3);
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      final future = container
          .read(pdfDocumentNotifierProvider('/docs/one.pdf').future);
      final handle = await future;

      expect(handle.pageCount, 3);
      expect(fake.openedPaths, ['/docs/one.pdf']);
    });

    test('exposes PdfOpenError through AsyncValue.error', () async {
      final fake = FakePdfRasterPort();
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      final future =
          container.read(pdfDocumentNotifierProvider('/missing.pdf').future);

      await expectLater(future, throwsA(isA<PdfOpenError>()));
    });

    test('closing the provider closes the handle on the cache/port',
        () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/docs/one.pdf', pageCount: 2);
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);

      // Keep the provider alive long enough to resolve.
      final sub = container.listen(
        pdfDocumentNotifierProvider('/docs/one.pdf'),
        (_, __) {},
      );
      await container
          .read(pdfDocumentNotifierProvider('/docs/one.pdf').future);
      expect(fake.closedHandleIds, isEmpty);

      // Dropping the last subscription + disposing the container triggers
      // autoDispose → ref.onDispose → close on the handle.
      sub.close();
      container.dispose();

      // The close is async in the notifier; tiny pump lets the
      // microtask queue drain.
      await Future<void>.delayed(Duration.zero);
      expect(fake.closedHandleIds, ['/docs/one.pdf']);
    });
  });

  group('pdfPageImageProvider', () {
    test('renders page bytes via the cache', () async {
      final fake = FakePdfRasterPort()
        ..register(path: '/docs/one.pdf', pageCount: 2);
      final container = ProviderContainer(overrides: [
        pdfRasterPortProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      final bytes = await container.read(
        pdfPageImageProvider(
          const PdfPageImageKey(
            filePath: '/docs/one.pdf',
            pageNumber: 1,
            targetWidth: 400,
            targetHeight: 560,
          ),
        ).future,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(fake.renderCalls, hasLength(1));
      expect(fake.renderCalls.first.pageNumber, 1);
    });
  });
}
