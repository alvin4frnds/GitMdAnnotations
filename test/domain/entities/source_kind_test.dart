import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/source_kind.dart';

void main() {
  group('SourceKind', () {
    test('exposes markdown, pdf, and svg variants in declaration order', () {
      expect(
        SourceKind.values,
        orderedEquals(<SourceKind>[
          SourceKind.markdown,
          SourceKind.pdf,
          SourceKind.svg,
        ]),
      );
    });

    test('name property is the dart identifier', () {
      expect(SourceKind.markdown.name, 'markdown');
      expect(SourceKind.pdf.name, 'pdf');
      expect(SourceKind.svg.name, 'svg');
    });
  });
}
