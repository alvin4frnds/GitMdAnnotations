import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';

void main() {
  group('MarkdownAnchor', () {
    test('constructs with positive lineNumber and sourceSha', () {
      final a = MarkdownAnchor(lineNumber: 47, sourceSha: 'a3f91c');
      expect(a.lineNumber, 47);
      expect(a.sourceSha, 'a3f91c');
    });

    test('value equality and hashCode', () {
      final a = MarkdownAnchor(lineNumber: 10, sourceSha: 's');
      final b = MarkdownAnchor(lineNumber: 10, sourceSha: 's');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different lineNumber is unequal', () {
      final a = MarkdownAnchor(lineNumber: 10, sourceSha: 's');
      final b = MarkdownAnchor(lineNumber: 11, sourceSha: 's');
      expect(a, isNot(equals(b)));
    });

    test('is assignable to Anchor', () {
      final Anchor a = MarkdownAnchor(lineNumber: 1, sourceSha: 's');
      expect(a, isA<MarkdownAnchor>());
    });

    test('throws ArgumentError when lineNumber is zero', () {
      expect(
        () => MarkdownAnchor(lineNumber: 0, sourceSha: 's'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when lineNumber is negative', () {
      expect(
        () => MarkdownAnchor(lineNumber: -1, sourceSha: 's'),
        throwsArgumentError,
      );
    });

    test('toString includes line and sha', () {
      final a = MarkdownAnchor(lineNumber: 47, sourceSha: 'abc');
      final s = a.toString();
      expect(s, contains('47'));
      expect(s, contains('abc'));
    });
  });

  group('Rect', () {
    test('constructs with four doubles', () {
      const r = Rect(left: 1, top: 2, right: 3, bottom: 4);
      expect(r.left, 1);
      expect(r.top, 2);
      expect(r.right, 3);
      expect(r.bottom, 4);
    });

    test('value equality', () {
      const a = Rect(left: 1, top: 2, right: 3, bottom: 4);
      const b = Rect(left: 1, top: 2, right: 3, bottom: 4);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different right is unequal', () {
      const a = Rect(left: 1, top: 2, right: 3, bottom: 4);
      const b = Rect(left: 1, top: 2, right: 9, bottom: 4);
      expect(a, isNot(equals(b)));
    });
  });

  group('PdfAnchor', () {
    const bbox = Rect(left: 120, top: 340, right: 180, bottom: 380);

    test('constructs with positive page, bbox, sourceSha', () {
      final a = PdfAnchor(page: 3, bbox: bbox, sourceSha: 'abc');
      expect(a.page, 3);
      expect(a.bbox, bbox);
      expect(a.sourceSha, 'abc');
    });

    test('value equality and hashCode', () {
      final a = PdfAnchor(page: 2, bbox: bbox, sourceSha: 's');
      final b = PdfAnchor(page: 2, bbox: bbox, sourceSha: 's');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different page is unequal', () {
      final a = PdfAnchor(page: 1, bbox: bbox, sourceSha: 's');
      final b = PdfAnchor(page: 2, bbox: bbox, sourceSha: 's');
      expect(a, isNot(equals(b)));
    });

    test('is assignable to Anchor', () {
      final Anchor a = PdfAnchor(page: 1, bbox: bbox, sourceSha: 's');
      expect(a, isA<PdfAnchor>());
    });

    test('throws ArgumentError when page is zero', () {
      expect(
        () => PdfAnchor(page: 0, bbox: bbox, sourceSha: 's'),
        throwsArgumentError,
      );
    });
  });

  group('Anchor sealed switch', () {
    test('exhaustive switch over Anchor compiles and resolves', () {
      final Anchor a = MarkdownAnchor(lineNumber: 1, sourceSha: 's');
      final String tag = switch (a) {
        MarkdownAnchor() => 'md',
        PdfAnchor() => 'pdf',
      };
      expect(tag, 'md');
    });
  });
}
