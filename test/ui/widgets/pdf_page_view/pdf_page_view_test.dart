import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/pdf_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/pdf_document_handle.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/ui/widgets/pdf_page_view/pdf_page_tile.dart';
import 'package:gitmdannotations_tablet/ui/widgets/pdf_page_view/pdf_page_view.dart';

/// A distinct PNG signature per page so `findsNWidgets` checks on
/// `Image.memory` can tell pages apart. Any 8-byte buffer works — the
/// test asserts on widget count, not pixel content.
Uint8List _pagePng(int pageNumber) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, pageNumber]);

Widget _host({
  required FakePdfRasterPort port,
  required String filePath,
  void Function(int page, Offset localOffsetInPage)? onPageTap,
  void Function(int page)? onVisiblePageChanged,
}) {
  return ProviderScope(
    overrides: [pdfRasterPortProvider.overrideWithValue(port)],
    child: MaterialApp(
      home: Scaffold(
        body: _DocHost(
          filePath: filePath,
          onPageTap: onPageTap,
          onVisiblePageChanged: onVisiblePageChanged,
        ),
      ),
    ),
  );
}

/// Tiny Consumer that resolves the document handle from the provider
/// and passes it to [PdfPageView]. Keeps tests free of the
/// notifier-watch boilerplate.
class _DocHost extends ConsumerWidget {
  const _DocHost({
    required this.filePath,
    this.onPageTap,
    this.onVisiblePageChanged,
  });

  final String filePath;
  final void Function(int page, Offset localOffsetInPage)? onPageTap;
  final void Function(int page)? onVisiblePageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pdfDocumentNotifierProvider(filePath));
    return async.when(
      data: (handle) => PdfPageView(
        filePath: filePath,
        handle: handle,
        onPageTap: onPageTap,
        onVisiblePageChanged: onVisiblePageChanged,
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('error: $e'),
    );
  }
}

void main() {
  testWidgets('renders page tiles for a 3-page handle', (tester) async {
    // Tall viewport so all three A4-aspect tiles realize into the
    // ListView cache (cacheExtent defaults to ~250px, not enough to
    // realize page 3 without this override).
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/three.pdf',
        pageCount: 3,
        pagePngs: {1: _pagePng(1), 2: _pagePng(2), 3: _pagePng(3)},
      );
    await tester.pumpWidget(_host(port: port, filePath: '/docs/three.pdf'));
    await tester.pump(); // handle resolves
    await tester.pump(const Duration(milliseconds: 50)); // render futures

    expect(find.byType(PdfPageTile), findsNWidgets(3));
  });

  testWidgets('each rendered page shows an Image.memory once bytes arrive',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(path: '/docs/one.pdf', pageCount: 1, pagePngs: {
        1: _pagePng(1),
      });
    await tester.pumpWidget(_host(port: port, filePath: '/docs/one.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('tap on a page fires onPageTap with page + local offset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(path: '/docs/one.pdf', pageCount: 1, pagePngs: {
        1: _pagePng(1),
      });
    int? tappedPage;
    Offset? tappedOffset;
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/one.pdf',
      onPageTap: (p, o) {
        tappedPage = p;
        tappedOffset = o;
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tile = find.byType(PdfPageTile).first;
    final topLeft = tester.getTopLeft(tile);
    await tester.tapAt(topLeft + const Offset(30, 40));
    await tester.pump();

    expect(tappedPage, 1);
    expect(tappedOffset, isNotNull);
    // Local offset is relative to the tile — should be near (30, 40).
    expect(tappedOffset!.dx, closeTo(30, 2));
    expect(tappedOffset!.dy, closeTo(40, 2));
  });

  testWidgets('scripted render error surfaces a page-level error box',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(path: '/docs/one.pdf', pageCount: 1)
      ..scriptRenderError('boom');
    await tester.pumpWidget(_host(port: port, filePath: '/docs/one.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Failed to render page'), findsOneWidget);
  });

  testWidgets('renderPage is called for visible pages only (lazy load)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/many.pdf',
        pageCount: 20,
        pagePngs: {for (var i = 1; i <= 20; i++) i: _pagePng(i)},
      );
    await tester.pumpWidget(_host(port: port, filePath: '/docs/many.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // With a 400-tall viewport and ~840-tall pages (600*1.4 aspect),
    // at most 2–3 pages lay out — certainly not all 20.
    expect(
      port.renderCalls.length,
      lessThan(20),
      reason: 'lazy rendering: ListView.builder must not realize every page',
    );
    expect(
      port.renderCalls.length,
      greaterThanOrEqualTo(1),
      reason: 'at least the first page should render',
    );
  });

  testWidgets('onVisiblePageChanged fires after scrolling to a later page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/many.pdf',
        pageCount: 5,
        pagePngs: {for (var i = 1; i <= 5; i++) i: _pagePng(i)},
      );
    final visiblePages = <int>[];
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/many.pdf',
      onVisiblePageChanged: visiblePages.add,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Scroll a large distance.
    await tester.drag(find.byType(PdfPageView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(visiblePages, isNotEmpty);
    expect(visiblePages.last, greaterThan(1));
  });
}

/// Expose the handle so tests can assert on `PdfDocumentHandle.pageCount`
/// independently. Unused in current tests but retained as a sanity
/// check for future scroll/zoom coverage.
// ignore: unused_element
PdfDocumentHandle _mkHandle(String id, int pages) =>
    PdfDocumentHandle(id: id, pageCount: pages);
