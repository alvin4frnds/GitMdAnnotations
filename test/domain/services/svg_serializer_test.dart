import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/anchor.dart';
import 'package:gitmdscribe/domain/entities/stroke.dart';
import 'package:gitmdscribe/domain/entities/stroke_group.dart';
import 'package:gitmdscribe/domain/services/svg_serializer.dart';

String _readGolden(String name) =>
    File('test/golden/$name').readAsStringSync();

void main() {
  const serializer = SvgSerializer();
  const source = SvgSource(sourceFile: '02-spec.md', sourceSha: 'a3f91c');

  group('SvgSerializer — golden: one group, one stroke, two points', () {
    test('matches test/golden/svg_one_group_one_stroke.svg', () {
      final group = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 47, sourceSha: 'a3f91c'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 120, y: 340, pressure: 0.5),
              StrokePoint(x: 340, y: 120, pressure: 0.5),
            ],
            color: '#DC2626',
            strokeWidth: 2.1,
          ),
        ],
      );

      final out = serializer.serialize([group], source);
      expect(out, _readGolden('svg_one_group_one_stroke.svg'));
    });
  });

  group('SvgSerializer — golden: multi-group markdown', () {
    test('matches test/golden/svg_multi_group.svg', () {
      final groupA = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 10, sourceSha: 'abc123'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 1, y: 2, pressure: 0.5),
              StrokePoint(x: 3, y: 4, pressure: 0.5),
            ],
            color: '#DC2626',
            strokeWidth: 2.1,
          ),
          Stroke(
            points: [
              StrokePoint(x: 5, y: 6, pressure: 0.5),
              StrokePoint(x: 7, y: 8, pressure: 0.5),
              StrokePoint(x: 9, y: 10, pressure: 0.5),
            ],
            color: '#2563EB',
            strokeWidth: 3,
          ),
        ],
      );
      final groupB = StrokeGroup(
        id: 'stroke-group-B',
        anchor: MarkdownAnchor(lineNumber: 102, sourceSha: 'abc123'),
        timestamp: DateTime.utc(2026, 4, 20, 10),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 50, y: 60, pressure: 0.5),
              StrokePoint(x: 70, y: 80, pressure: 0.5),
            ],
            color: '#059669',
            strokeWidth: 1.5,
          ),
        ],
      );

      final out = serializer.serialize(
        [groupA, groupB],
        const SvgSource(sourceFile: '02-spec.md', sourceSha: 'abc123'),
      );
      expect(out, _readGolden('svg_multi_group.svg'));
    });
  });

  group('SvgSerializer — golden: PDF anchor', () {
    test('matches test/golden/svg_pdf_anchor.svg', () {
      final group = StrokeGroup(
        id: 'stroke-group-A',
        anchor: PdfAnchor(
          page: 3,
          bbox: const Rect(left: 120, top: 340, right: 180, bottom: 380),
          sourceSha: 'deadbeef',
        ),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 120, y: 340, pressure: 0.5),
              StrokePoint(x: 180, y: 380, pressure: 0.5),
            ],
            color: '#DC2626',
            strokeWidth: 2,
          ),
        ],
      );
      final out = serializer.serialize(
        [group],
        const SvgSource(sourceFile: 'spec.pdf', sourceSha: 'deadbeef'),
      );
      expect(out, _readGolden('svg_pdf_anchor.svg'));
    });
  });

  group('SvgSerializer — golden: single-point stroke', () {
    test('matches test/golden/svg_single_point_stroke.svg (no L segment)', () {
      final group = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 120, y: 340, pressure: 0.5)],
            color: '#DC2626',
            strokeWidth: 2,
          ),
        ],
      );
      final out = serializer.serialize(
        [group],
        const SvgSource(sourceFile: '02-spec.md', sourceSha: 'abc'),
      );
      expect(out, _readGolden('svg_single_point_stroke.svg'));
    });
  });

  group('SvgSerializer — golden: empty stroke + empty group', () {
    test('matches test/golden/svg_empty_stroke_and_group.svg', () {
      final groupA = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: const [],
            color: '#DC2626',
            strokeWidth: 2,
          ),
        ],
      );
      final groupB = StrokeGroup(
        id: 'stroke-group-B',
        anchor: MarkdownAnchor(lineNumber: 2, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 23),
        strokes: const [],
      );
      final out = serializer.serialize(
        [groupA, groupB],
        const SvgSource(sourceFile: '02-spec.md', sourceSha: 'abc'),
      );
      expect(out, _readGolden('svg_empty_stroke_and_group.svg'));
    });
  });

  group('SvgSerializer — color normalization', () {
    test('lowercase hex input is canonicalized to uppercase in output', () {
      final group = StrokeGroup(
        id: 'g',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
            color: '#dc2626',
            strokeWidth: 2,
          ),
        ],
      );
      final out = serializer.serialize([group], source);
      expect(out, contains('stroke="#DC2626"'));
      expect(out, isNot(contains('stroke="#dc2626"')));
    });
  });

  group('SvgSerializer — timestamp UTC conversion', () {
    test('local DateTime is serialized as UTC ISO-8601 with trailing Z', () {
      final local = DateTime(2026, 4, 20, 5, 14, 22);
      final u = local.toUtc();
      final expectedTs = '${u.year.toString().padLeft(4, '0')}'
          '-${u.month.toString().padLeft(2, '0')}'
          '-${u.day.toString().padLeft(2, '0')}'
          'T${u.hour.toString().padLeft(2, '0')}'
          ':${u.minute.toString().padLeft(2, '0')}'
          ':${u.second.toString().padLeft(2, '0')}Z';

      final group = StrokeGroup(
        id: 'g',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
        timestamp: local,
        strokes: [
          Stroke(
            points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
            color: '#DC2626',
            strokeWidth: 2,
          ),
        ],
      );
      final out = serializer.serialize([group], source);

      expect(expectedTs, hasLength(20));
      expect(expectedTs.endsWith('Z'), isTrue);
      expect(out, contains('data-timestamp="$expectedTs"'));
    });
  });

  group('SvgSerializer — attribute escaping', () {
    test('& < > " in sourceFile are XML-escaped in the attribute value', () {
      const weirdSource = SvgSource(sourceFile: 'a&b<c>"d', sourceSha: 'abc');
      final out = serializer.serialize(const [], weirdSource);
      expect(out, contains('data-source-file="a&amp;b&lt;c&gt;&quot;d"'));
    });
  });

  group('SvgSerializer — golden: zero groups', () {
    test('matches test/golden/svg_no_groups.svg (empty root)', () {
      final out = serializer.serialize(const [], source);
      expect(out, _readGolden('svg_no_groups.svg'));
    });
  });

  group('SvgSerializer — determinism', () {
    test('serializing the same input twice yields byte-identical output', () {
      final group = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 47, sourceSha: 'a3f91c'),
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 120, y: 340, pressure: 0.5),
              StrokePoint(x: 340, y: 120, pressure: 0.5),
            ],
            color: '#DC2626',
            strokeWidth: 2.1,
          ),
        ],
      );
      final a = serializer.serialize([group], source);
      final b = serializer.serialize([group], source);
      expect(a, b);
      expect(a.codeUnits, b.codeUnits);
    });
  });

  group('SvgSerializer — per-stroke opacity', () {
    test('default 0.9 → emits opacity="0.9" (backwards-compatible)', () {
      final serializer = const SvgSerializer();
      final group = StrokeGroup(
        id: 'stroke-group-A',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 21, 12),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
            color: '#DC2626',
            strokeWidth: 2,
          ),
        ],
      );
      final out = serializer.serialize(
        [group],
        const SvgSource(sourceFile: 'x', sourceSha: 'y'),
      );
      expect(out, contains('opacity="0.9"'));
    });

    test('highlighter stroke (opacity 0.35) → emits opacity="0.35"', () {
      final serializer = const SvgSerializer();
      final group = StrokeGroup(
        id: 'stroke-group-B',
        anchor: MarkdownAnchor(lineNumber: 2, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 21, 12),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
            color: '#F59E0B',
            strokeWidth: 16,
            opacity: 0.35,
          ),
        ],
      );
      final out = serializer.serialize(
        [group],
        const SvgSource(sourceFile: 'x', sourceSha: 'y'),
      );
      expect(out, contains('opacity="0.35"'));
      expect(out, isNot(contains('opacity="0.9"')));
    });
  });
}
