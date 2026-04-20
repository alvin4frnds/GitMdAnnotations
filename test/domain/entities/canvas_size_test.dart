import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';

/// Domain-level value object [CanvasSize]. `Size` from `dart:ui` is a Flutter
/// import and therefore forbidden in `lib/domain/**` (IMPLEMENTATION.md §2.6);
/// the annotation module uses [CanvasSize] instead.
void main() {
  group('CanvasSize construction', () {
    test('constructs with positive dimensions', () {
      final c = CanvasSize(width: 800, height: 1200);
      expect(c.width, 800);
      expect(c.height, 1200);
    });
  });

  group('CanvasSize equality', () {
    test('equal dimensions are equal (and hash-equal)', () {
      // Construct with non-const so canonicalization does not short-circuit
      // to a single instance; the `==` / `hashCode` implementation is what
      // makes two distinct allocations compare equal.
      final a = CanvasSize(width: 800.0 + 0.0, height: 1200.0 + 0.0);
      final b = CanvasSize(width: 800.0 + 0.0, height: 1200.0 + 0.0);
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('unequal dimensions are unequal', () {
      final a = CanvasSize(width: 800.0 + 0.0, height: 1200.0 + 0.0);
      final b = CanvasSize(width: 801.0 + 0.0, height: 1200.0 + 0.0);
      final c = CanvasSize(width: 800.0 + 0.0, height: 1201.0 + 0.0);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });
  });

  group('CanvasSize validation', () {
    test('rejects zero width with ArgumentError', () {
      expect(
        () => CanvasSize(width: 0, height: 1200),
        throwsArgumentError,
      );
    });

    test('rejects zero height with ArgumentError', () {
      expect(
        () => CanvasSize(width: 800, height: 0),
        throwsArgumentError,
      );
    });

    test('rejects negative width with ArgumentError', () {
      expect(
        () => CanvasSize(width: -1, height: 1200),
        throwsArgumentError,
      );
    });

    test('rejects negative height with ArgumentError', () {
      expect(
        () => CanvasSize(width: 800, height: -1),
        throwsArgumentError,
      );
    });

    test('rejects NaN width with ArgumentError', () {
      expect(
        () => CanvasSize(width: double.nan, height: 1200),
        throwsArgumentError,
      );
    });

    test('rejects NaN height with ArgumentError', () {
      expect(
        () => CanvasSize(width: 800, height: double.nan),
        throwsArgumentError,
      );
    });

    test('rejects infinite width with ArgumentError', () {
      expect(
        () => CanvasSize(width: double.infinity, height: 1200),
        throwsArgumentError,
      );
    });

    test('rejects infinite height with ArgumentError', () {
      expect(
        () => CanvasSize(width: 800, height: double.infinity),
        throwsArgumentError,
      );
    });
  });

  group('CanvasSize toString', () {
    test('toString contains both dimensions', () {
      final c = CanvasSize(width: 812.5, height: 1234.75);
      final str = c.toString();
      expect(str, contains('812.5'));
      expect(str, contains('1234.75'));
    });
  });
}
