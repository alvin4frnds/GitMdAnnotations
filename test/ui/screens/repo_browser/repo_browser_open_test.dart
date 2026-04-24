import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/ui/screens/repo_browser/repo_browser_screen.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_md/spec_reader_md_screen.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart';
import 'package:gitmdscribe/ui/screens/spec_reader_svg/spec_reader_svg_screen.dart';

void main() {
  group('readerScreenForBrowserPath', () {
    test('.md -> SpecReaderMdScreen.fromPath (jobRef null)', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'docs/one.md',
      );
      expect(w, isA<SpecReaderMdScreen>());
      final md = w! as SpecReaderMdScreen;
      expect(md.jobRef, isNull);
      expect(md.filePath, '/repo/docs/one.md');
    });

    test('.MARKDOWN (uppercase) still routes to md reader', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'docs/one.MARKDOWN',
      );
      expect(w, isA<SpecReaderMdScreen>());
      expect((w! as SpecReaderMdScreen).filePath, '/repo/docs/one.MARKDOWN');
    });

    test('.pdf -> SpecReaderPdfScreen with null jobRef', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'attachments/deck.pdf',
      );
      expect(w, isA<SpecReaderPdfScreen>());
      final pdf = w! as SpecReaderPdfScreen;
      expect(pdf.jobRef, isNull);
      expect(pdf.filePath, '/repo/attachments/deck.pdf');
    });

    test('.svg -> SpecReaderSvgScreen with null jobRef', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'diagrams/flow.svg',
      );
      expect(w, isA<SpecReaderSvgScreen>());
      final svg = w! as SpecReaderSvgScreen;
      expect(svg.jobRef, isNull);
      expect(svg.filePath, '/repo/diagrams/flow.svg');
    });

    test('unknown extension -> null (no dispatch)', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'ci/pipeline.yaml',
      );
      expect(w, isNull);
    });

    test('no extension -> null', () {
      final w = readerScreenForBrowserPath(
        workdir: '/repo',
        relPath: 'README',
      );
      expect(w, isNull);
    });
  });
}
