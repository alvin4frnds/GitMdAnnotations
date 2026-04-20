import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/pdf_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_pdf_raster_port.dart';
import 'package:gitmdannotations_tablet/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/ink_overlay.dart';
import 'package:gitmdannotations_tablet/ui/widgets/pdf_page_view/pdf_page_tile.dart';

final _jobRef = JobRef(
  repo: const RepoRef(owner: 'demo', name: 'payments-api'),
  jobId: 'spec-invoice-pdf-redesign',
);

final _t0 = DateTime.utc(2026, 4, 20, 9, 14, 22);

Uint8List _pagePng(int p) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, p]);

Widget _host({
  required FakePdfRasterPort port,
  required String filePath,
  required JobRef jobRef,
}) {
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(FakeClock(_t0)),
      idGeneratorProvider.overrideWithValue(FakeIdGenerator()),
      pdfRasterPortProvider.overrideWithValue(port),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: Scaffold(
        body: SpecReaderPdfScreen(filePath: filePath, jobRef: jobRef),
      ),
    ),
  );
}

ProviderContainer _containerFor(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(SpecReaderPdfScreen)),
  );
}

Future<void> _setLandscape(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders screen chrome + PDF page tiles', (tester) async {
    await _setLandscape(tester);
    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/mock.pdf',
        pageCount: 2,
        pagePngs: {1: _pagePng(1), 2: _pagePng(2)},
      );
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/mock.pdf',
      jobRef: _jobRef,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PdfPageTile), findsWidgets);
    expect(find.byType(InkOverlay), findsOneWidget);
    expect(find.text('spec-invoice-pdf-redesign'), findsOneWidget);
  });

  testWidgets('stylus down/move/up commits one StrokeGroup',
      (tester) async {
    await _setLandscape(tester);
    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/mock.pdf',
        pageCount: 1,
        pagePngs: {1: _pagePng(1)},
      );
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/mock.pdf',
      jobRef: _jobRef,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final centre = tester.getCenter(find.byType(InkOverlay));
    final g =
        await tester.startGesture(centre, kind: PointerDeviceKind.stylus);
    await tester.pump();
    await g.moveBy(const Offset(10, 10));
    await tester.pump();
    await g.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, hasLength(1));
  });

  testWidgets('touch gesture does NOT commit a StrokeGroup', (tester) async {
    await _setLandscape(tester);
    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/mock.pdf',
        pageCount: 1,
        pagePngs: {1: _pagePng(1)},
      );
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/mock.pdf',
      jobRef: _jobRef,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final centre = tester.getCenter(find.byType(InkOverlay));
    final g = await tester.startGesture(centre); // default: touch
    await tester.pump();
    await g.moveBy(const Offset(10, 10));
    await tester.pump();
    await g.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, isEmpty);
  });

  testWidgets('undo button removes the last committed group',
      (tester) async {
    await _setLandscape(tester);
    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/mock.pdf',
        pageCount: 1,
        pagePngs: {1: _pagePng(1)},
      );
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/mock.pdf',
      jobRef: _jobRef,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final centre = tester.getCenter(find.byType(InkOverlay));
    final g =
        await tester.startGesture(centre, kind: PointerDeviceKind.stylus);
    await tester.pump();
    await g.up();
    await tester.pump();

    final container = _containerFor(tester);
    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      isEmpty,
    );
  });

  testWidgets('redo button restores a previously undone group',
      (tester) async {
    await _setLandscape(tester);
    final port = FakePdfRasterPort()
      ..register(
        path: '/docs/mock.pdf',
        pageCount: 1,
        pagePngs: {1: _pagePng(1)},
      );
    await tester.pumpWidget(_host(
      port: port,
      filePath: '/docs/mock.pdf',
      jobRef: _jobRef,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final centre = tester.getCenter(find.byType(InkOverlay));
    final g =
        await tester.startGesture(centre, kind: PointerDeviceKind.stylus);
    await tester.pump();
    await g.up();
    await tester.pump();

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();

    final container = _containerFor(tester);
    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      hasLength(1),
    );
  });
}
