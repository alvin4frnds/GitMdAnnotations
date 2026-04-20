import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';

/// Invariant and boundary coverage for [Stroke] and [StrokePoint].
///
/// Sibling to `stroke_test.dart`, split by responsibility: this file owns the
/// pressure/coordinate boundary invariants, empty-stroke intermediate states,
/// and large-collection equality/hashing correctness (IMPLEMENTATION.md
/// §2.6 size-limit rule — split-by-responsibility, not alphabetic).
void main() {
  group('StrokePoint pressure boundaries', () {
    test('accepts pressure at minimum boundary 0.0', () {
      expect(
        () => StrokePoint(x: 1, y: 2, pressure: 0.0),
        returnsNormally,
      );
    });

    test('accepts pressure at maximum boundary 1.0', () {
      expect(
        () => StrokePoint(x: 1, y: 2, pressure: 1.0),
        returnsNormally,
      );
    });

    test('rejects pressure below 0.0 with ArgumentError', () {
      expect(
        () => StrokePoint(x: 1, y: 2, pressure: -0.0001),
        throwsArgumentError,
      );
    });

    test('rejects pressure above 1.0 with ArgumentError', () {
      expect(
        () => StrokePoint(x: 1, y: 2, pressure: 1.0001),
        throwsArgumentError,
      );
    });

    test('rejects NaN pressure with ArgumentError', () {
      expect(
        () => StrokePoint(x: 1, y: 2, pressure: double.nan),
        throwsArgumentError,
      );
    });
  });

  group('StrokePoint coordinate boundaries', () {
    test('accepts negative x and y coordinates', () {
      expect(
        () => StrokePoint(x: -10, y: -20, pressure: 0.5),
        returnsNormally,
      );
    });

    test(
      'accepts infinite x and y at the value-object level '
      '(coordinate clamping is a rendering concern, not an entity concern)',
      () {
        expect(
          () => StrokePoint(
            x: double.infinity,
            y: double.negativeInfinity,
            pressure: 0.5,
          ),
          returnsNormally,
        );
      },
    );

    test('rejects NaN x coordinate with ArgumentError', () {
      expect(
        () => StrokePoint(x: double.nan, y: 2, pressure: 0.5),
        throwsArgumentError,
      );
    });

    test('rejects NaN y coordinate with ArgumentError', () {
      expect(
        () => StrokePoint(x: 1, y: double.nan, pressure: 0.5),
        throwsArgumentError,
      );
    });
  });

  group('Stroke empty-points intermediate state', () {
    test(
      'constructs with zero points without error '
      '(valid intermediate state during stroke capture, before first sample)',
      () {
        expect(
          () => Stroke(
            points: const [],
            color: '#DC2626',
            strokeWidth: 2,
          ),
          returnsNormally,
        );
      },
    );

    test('two zero-point strokes with same color and width are equal', () {
      final a = Stroke(
        points: const [],
        color: '#DC2626',
        strokeWidth: 2,
      );
      final b = Stroke(
        points: const [],
        color: '#DC2626',
        strokeWidth: 2,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('Stroke huge point sets', () {
    List<StrokePoint> makePoints(int n) => List.generate(
          n,
          (i) => StrokePoint(x: i.toDouble(), y: i * 2.0, pressure: 0.5),
        );

    test('two strokes with 10,000 identical points are equal and hash-equal', () {
      final pointsA = makePoints(10000);
      final pointsB = makePoints(10000);
      final a = Stroke(points: pointsA, color: '#DC2626', strokeWidth: 2);
      final b = Stroke(points: pointsB, color: '#DC2626', strokeWidth: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test(
      'two strokes with 10,000 points differing only at the last index are unequal',
      () {
        final pointsA = makePoints(10000);
        final pointsB = makePoints(10000);
        pointsB[pointsB.length - 1] = StrokePoint(
          x: -1,
          y: -1,
          pressure: 0.5,
        );
        final a = Stroke(points: pointsA, color: '#DC2626', strokeWidth: 2);
        final b = Stroke(points: pointsB, color: '#DC2626', strokeWidth: 2);
        expect(a, isNot(equals(b)));
      },
    );
  });
}
