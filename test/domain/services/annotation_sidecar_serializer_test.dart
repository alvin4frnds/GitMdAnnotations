import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/anchor.dart';
import 'package:gitmdscribe/domain/entities/stroke.dart';
import 'package:gitmdscribe/domain/entities/stroke_group.dart';
import 'package:gitmdscribe/domain/services/annotation_sidecar_serializer.dart';
import 'package:gitmdscribe/domain/services/svg_serializer.dart';

void main() {
  group('AnnotationSidecarSerializer', () {
    final source = const SvgSource(sourceFile: '02-spec.md', sourceSha: 'abc');

    test('empty groups emits a valid top-level object with empty groups array',
        () {
      final out = const AnnotationSidecarSerializer(canonicalWidth: 900)
          .serialize(const [], source);
      final parsed = jsonDecode(out) as Map<String, Object?>;
      expect(parsed['schemaVersion'], 1);
      expect(parsed['sourceFile'], '02-spec.md');
      expect(parsed['sourceSha'], 'abc');
      expect(parsed['canonicalWidth'], 900);
      expect(parsed['groups'], <Object?>[]);
      expect(out.endsWith('\n'), isTrue, reason: 'trailing newline');
    });

    test('round-trips a markdown-anchored group with one stroke', () {
      final group = StrokeGroup(
        id: 'g1',
        anchor: MarkdownAnchor(lineNumber: 42, sourceSha: 'abc'),
        timestamp: DateTime.utc(2026, 4, 21, 9, 14, 22),
        strokes: [
          Stroke(
            points: [
              StrokePoint(x: 10, y: 20, pressure: 0.5),
              StrokePoint(x: 30, y: 40, pressure: 0.6),
            ],
            color: '#dc2626',
            strokeWidth: 2.1,
            opacity: 0.9,
          ),
        ],
      );
      final out = const AnnotationSidecarSerializer(canonicalWidth: 900)
          .serialize([group], source);
      final parsed = jsonDecode(out) as Map<String, Object?>;
      final groups = parsed['groups'] as List<Object?>;
      expect(groups, hasLength(1));
      final g = groups.single as Map<String, Object?>;
      expect(g['id'], 'g1');
      expect(g['timestamp'], '2026-04-21T09:14:22Z');
      final anchor = g['anchor'] as Map<String, Object?>;
      expect(anchor['kind'], 'markdown');
      expect(anchor['lineNumber'], 42);
      expect(anchor['sourceSha'], 'abc');
      final strokes = g['strokes'] as List<Object?>;
      expect(strokes, hasLength(1));
      final s = strokes.single as Map<String, Object?>;
      // Hex upper-cased to match the SVG serializer's canonicalization.
      expect(s['color'], '#DC2626');
      expect(s['strokeWidth'], 2.1);
      expect(s['opacity'], 0.9);
      final pts = s['points'] as List<Object?>;
      expect(pts, hasLength(2));
      expect((pts.first as Map)['x'], 10);
      expect((pts.first as Map)['pressure'], 0.5);
    });

    test('PDF anchor serializes with page + bbox + sourceSha', () {
      final group = StrokeGroup(
        id: 'g2',
        anchor: PdfAnchor(
          page: 3,
          bbox: const Rect(left: 1, top: 2, right: 3, bottom: 4),
          sourceSha: 'xyz',
        ),
        timestamp: DateTime.utc(2026, 4, 21),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 0, y: 0, pressure: 0)],
            color: '#000000',
            strokeWidth: 1,
          ),
        ],
      );
      final out = const AnnotationSidecarSerializer(canonicalWidth: 900)
          .serialize([group], source);
      final g = (jsonDecode(out) as Map)['groups'][0] as Map<String, Object?>;
      final anchor = g['anchor'] as Map<String, Object?>;
      expect(anchor['kind'], 'pdf');
      expect(anchor['page'], 3);
      expect((anchor['bbox'] as Map)['left'], 1);
      expect((anchor['bbox'] as Map)['bottom'], 4);
      expect(anchor['sourceSha'], 'xyz');
    });

    test('determinism: same input → byte-identical output', () {
      final group = StrokeGroup(
        id: 'g',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'a'),
        timestamp: DateTime.utc(2026, 1, 1),
        strokes: [
          Stroke(
            points: [StrokePoint(x: 1, y: 2, pressure: 0.1)],
            color: '#ABCDEF',
            strokeWidth: 1,
          ),
        ],
      );
      final s = const AnnotationSidecarSerializer(canonicalWidth: 900);
      expect(s.serialize([group], source), s.serialize([group], source));
    });
  });
}
