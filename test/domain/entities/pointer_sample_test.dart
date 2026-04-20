import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';

/// Domain-level value object [PointerSample] + [PointerKind] enum tests.
///
/// The UI layer converts Flutter's `PointerEvent` to a [PointerSample] before
/// handing it to the annotation session — the domain stays Flutter-free
/// (IMPLEMENTATION.md §2.6). Validation invariants mirror [StrokePoint] from
/// T1: NaN forbidden on any numeric, pressure constrained to `[0, 1]`.
void main() {
  group('PointerKind enum', () {
    test('enumerates exactly the six domain-relevant pointer kinds', () {
      // Only kinds the domain cares about. Anything else in Flutter's
      // PointerDeviceKind maps to `unknown` at the UI seam.
      expect(PointerKind.values, <PointerKind>[
        PointerKind.stylus,
        PointerKind.invertedStylus,
        PointerKind.touch,
        PointerKind.mouse,
        PointerKind.trackpad,
        PointerKind.unknown,
      ]);
    });
  });

  group('PointerSample construction', () {
    test('accepts a well-formed stylus sample', () {
      final sample = PointerSample(
        x: 10,
        y: 20,
        pressure: 0.5,
        kind: PointerKind.stylus,
        timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
      );
      expect(sample.x, 10);
      expect(sample.y, 20);
      expect(sample.pressure, 0.5);
      expect(sample.kind, PointerKind.stylus);
      expect(sample.timestamp, DateTime.utc(2026, 4, 20, 9, 14, 22));
    });

    test('rejects NaN x with ArgumentError', () {
      expect(
        () => PointerSample(
          x: double.nan,
          y: 0,
          pressure: 0.5,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('rejects NaN y with ArgumentError', () {
      expect(
        () => PointerSample(
          x: 0,
          y: double.nan,
          pressure: 0.5,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('rejects NaN pressure with ArgumentError', () {
      expect(
        () => PointerSample(
          x: 0,
          y: 0,
          pressure: double.nan,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('rejects pressure below 0.0', () {
      expect(
        () => PointerSample(
          x: 0,
          y: 0,
          pressure: -0.0001,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('rejects pressure above 1.0', () {
      expect(
        () => PointerSample(
          x: 0,
          y: 0,
          pressure: 1.0001,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('accepts pressure exactly at 0.0 boundary', () {
      expect(
        () => PointerSample(
          x: 0,
          y: 0,
          pressure: 0.0,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        returnsNormally,
      );
    });

    test('accepts pressure exactly at 1.0 boundary', () {
      expect(
        () => PointerSample(
          x: 0,
          y: 0,
          pressure: 1.0,
          kind: PointerKind.stylus,
          timestamp: DateTime.utc(2026),
        ),
        returnsNormally,
      );
    });
  });
}
