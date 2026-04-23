import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/services/markdown_line_resolver.dart';

void main() {
  group('resolveMarkdownLine', () {
    test('stroke at the top → line 1', () {
      expect(
        resolveMarkdownLine(sampleY: 0, contentHeight: 1000, totalLines: 100),
        1,
      );
    });

    test('stroke at the bottom → last line', () {
      expect(
        resolveMarkdownLine(
          sampleY: 1000,
          contentHeight: 1000,
          totalLines: 100,
        ),
        100,
      );
    });

    test('stroke at 50% → roughly middle line', () {
      final line = resolveMarkdownLine(
        sampleY: 500,
        contentHeight: 1000,
        totalLines: 100,
      );
      expect(line, inInclusiveRange(49, 52));
    });

    test('stroke at 25% → first quarter of lines', () {
      final line = resolveMarkdownLine(
        sampleY: 250,
        contentHeight: 1000,
        totalLines: 100,
      );
      expect(line, inInclusiveRange(24, 27));
    });

    test('stroke above content → clamped to line 1', () {
      expect(
        resolveMarkdownLine(
          sampleY: -50,
          contentHeight: 1000,
          totalLines: 100,
        ),
        1,
      );
    });

    test('stroke past bottom → clamped to last line', () {
      expect(
        resolveMarkdownLine(
          sampleY: 2000,
          contentHeight: 1000,
          totalLines: 100,
        ),
        100,
      );
    });

    test('single-line spec → always line 1', () {
      expect(
        resolveMarkdownLine(
          sampleY: 500,
          contentHeight: 1000,
          totalLines: 1,
        ),
        1,
      );
    });

    test('zero height (layout race) → line 1', () {
      expect(
        resolveMarkdownLine(sampleY: 42, contentHeight: 0, totalLines: 50),
        1,
      );
    });

    test('NaN coordinates → line 1 (safety)', () {
      expect(
        resolveMarkdownLine(
          sampleY: double.nan,
          contentHeight: 1000,
          totalLines: 50,
        ),
        1,
      );
      expect(
        resolveMarkdownLine(
          sampleY: 500,
          contentHeight: double.nan,
          totalLines: 50,
        ),
        1,
      );
    });

    test('rejects totalLines < 1', () {
      expect(
        () => resolveMarkdownLine(
          sampleY: 0,
          contentHeight: 100,
          totalLines: 0,
        ),
        throwsArgumentError,
      );
    });

    test('distinct Y values map to distinct lines (approximately)', () {
      final topLine = resolveMarkdownLine(
        sampleY: 100,
        contentHeight: 1000,
        totalLines: 100,
      );
      final bottomLine = resolveMarkdownLine(
        sampleY: 900,
        contentHeight: 1000,
        totalLines: 100,
      );
      expect(topLine, lessThan(bottomLine));
      expect(bottomLine - topLine, greaterThan(50));
    });
  });

  group('countMarkdownLines', () {
    test('empty string → 1', () {
      expect(countMarkdownLines(''), 1);
    });

    test('single line without trailing newline', () {
      expect(countMarkdownLines('hello'), 1);
    });

    test('single line with trailing newline', () {
      expect(countMarkdownLines('hello\n'), 1);
    });

    test('two lines separated by newline', () {
      expect(countMarkdownLines('one\ntwo'), 2);
    });

    test('two lines with trailing newline', () {
      expect(countMarkdownLines('one\ntwo\n'), 2);
    });

    test('multiple blank lines count individually', () {
      expect(countMarkdownLines('a\n\n\nb'), 4);
    });

    test('CRLF: \\r does not add a line (only \\n counts)', () {
      expect(countMarkdownLines('one\r\ntwo\r\n'), 2);
    });
  });
}
