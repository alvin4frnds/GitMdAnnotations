import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';

void main() {
  group('Stroke', () {
    final p1 = StrokePoint(x: 120, y: 340, pressure: 0.5);
    final p2 = StrokePoint(x: 121, y: 341, pressure: 0.6);

    test('constructs with points, color, strokeWidth', () {
      final s = Stroke(
        points: [p1, p2],
        color: '#DC2626',
        strokeWidth: 2.1,
      );
      expect(s.points, [p1, p2]);
      expect(s.color, '#DC2626');
      expect(s.strokeWidth, 2.1);
    });

    test('equal fields produce equal strokes', () {
      final a = Stroke(
        points: [p1, p2],
        color: '#DC2626',
        strokeWidth: 2.1,
      );
      final b = Stroke(
        points: [p1, p2],
        color: '#DC2626',
        strokeWidth: 2.1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different point list makes strokes unequal', () {
      final a = Stroke(
        points: [p1],
        color: '#DC2626',
        strokeWidth: 2.1,
      );
      final b = Stroke(
        points: [p1, p2],
        color: '#DC2626',
        strokeWidth: 2.1,
      );
      expect(a, isNot(equals(b)));
    });

    test('accepts lowercase hex', () {
      expect(
        () => Stroke(
          points: [p1],
          color: '#dc2626',
          strokeWidth: 2,
        ),
        returnsNormally,
      );
    });

    test('throws ArgumentError on color missing leading #', () {
      expect(
        () => Stroke(
          points: [p1],
          color: 'DC2626',
          strokeWidth: 2,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on 3-digit shorthand hex', () {
      expect(
        () => Stroke(
          points: [p1],
          color: '#DCA',
          strokeWidth: 2,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on non-hex characters', () {
      expect(
        () => Stroke(
          points: [p1],
          color: '#ZZZZZZ',
          strokeWidth: 2,
        ),
        throwsArgumentError,
      );
    });

    test('toString includes color and point count', () {
      final s = Stroke(
        points: [p1, p2],
        color: '#DC2626',
        strokeWidth: 2,
      );
      final str = s.toString();
      expect(str, contains('#DC2626'));
      expect(str, contains('2'));
    });
  });

  group('StrokePoint', () {
    test('equal coordinates are equal', () {
      final a = StrokePoint(x: 1, y: 2, pressure: 0.5);
      final b = StrokePoint(x: 1, y: 2, pressure: 0.5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different pressure is unequal', () {
      final a = StrokePoint(x: 1, y: 2, pressure: 0.5);
      final b = StrokePoint(x: 1, y: 2, pressure: 0.6);
      expect(a, isNot(equals(b)));
    });
  });
}
