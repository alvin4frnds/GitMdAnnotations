import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';

void main() {
  final anchor = MarkdownAnchor(lineNumber: 47, sourceSha: 'abc');
  final stroke = Stroke(
    points: [StrokePoint(x: 1, y: 2, pressure: 0.5)],
    color: '#DC2626',
    strokeWidth: 2,
  );
  final ts = DateTime(2026, 4, 20, 9, 14, 22);

  group('StrokeGroup', () {
    test('constructs with id, anchor, timestamp, strokes', () {
      final g = StrokeGroup(
        id: 'stroke-group-A',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke],
      );
      expect(g.id, 'stroke-group-A');
      expect(g.anchor, anchor);
      expect(g.timestamp, ts);
      expect(g.strokes, [stroke]);
    });

    test('equal fields produce equal groups', () {
      final a = StrokeGroup(
        id: 'g1',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke],
      );
      final b = StrokeGroup(
        id: 'g1',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different stroke count makes groups unequal', () {
      final a = StrokeGroup(
        id: 'g1',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke],
      );
      final b = StrokeGroup(
        id: 'g1',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke, stroke],
      );
      expect(a, isNot(equals(b)));
    });

    test('throws ArgumentError on empty id', () {
      expect(
        () => StrokeGroup(
          id: '',
          anchor: anchor,
          timestamp: ts,
          strokes: const [],
        ),
        throwsArgumentError,
      );
    });

    test('toString includes id and stroke count', () {
      final g = StrokeGroup(
        id: 'stroke-group-A',
        anchor: anchor,
        timestamp: ts,
        strokes: [stroke, stroke],
      );
      final s = g.toString();
      expect(s, contains('stroke-group-A'));
      expect(s, contains('2'));
    });

    test(
      'constructs with zero strokes without error '
      '(valid during review of a not-yet-started group)',
      () {
        expect(
          () => StrokeGroup(
            id: 'stroke-group-A',
            anchor: anchor,
            timestamp: ts,
            strokes: const [],
          ),
          returnsNormally,
        );
      },
    );

    test(
      'two zero-stroke groups with same id, anchor, and timestamp '
      'are equal and hash-equal',
      () {
        final a = StrokeGroup(
          id: 'stroke-group-A',
          anchor: anchor,
          timestamp: ts,
          strokes: const [],
        );
        final b = StrokeGroup(
          id: 'stroke-group-A',
          anchor: anchor,
          timestamp: ts,
          strokes: const [],
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      },
    );
  });

  group('StrokeGroup huge stroke sets', () {
    Stroke makeStroke() => Stroke(
          points: List.generate(
            100,
            (i) => StrokePoint(x: i.toDouble(), y: i * 2.0, pressure: 0.5),
          ),
          color: '#DC2626',
          strokeWidth: 2,
        );

    test(
      'two groups of 500 strokes (100 points each) are equal and hash-equal',
      () {
        final strokesA = List.generate(500, (_) => makeStroke());
        final strokesB = List.generate(500, (_) => makeStroke());
        final a = StrokeGroup(
          id: 'g1',
          anchor: anchor,
          timestamp: ts,
          strokes: strokesA,
        );
        final b = StrokeGroup(
          id: 'g1',
          anchor: anchor,
          timestamp: ts,
          strokes: strokesB,
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      },
    );
  });
}
