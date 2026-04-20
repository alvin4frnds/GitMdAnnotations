import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/pointer_event_mapper.dart';

/// Helper to construct a stylus down event with a given position + pressure.
/// `PointerDownEvent.localPosition` defaults to `position` when no transform
/// is applied, which is what the mapper reads.
PointerDownEvent _downEvent({
  required Offset localPosition,
  double pressure = 1.0,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) {
  return PointerDownEvent(
    position: localPosition,
    pressure: pressure,
    kind: kind,
  );
}

void main() {
  const mapper = PointerEventMapper();

  group('PointerEventMapper.toKind', () {
    test('maps stylus -> stylus', () {
      expect(mapper.toKind(PointerDeviceKind.stylus), PointerKind.stylus);
    });

    test('maps invertedStylus -> invertedStylus', () {
      expect(
        mapper.toKind(PointerDeviceKind.invertedStylus),
        PointerKind.invertedStylus,
      );
    });

    test('maps touch -> touch', () {
      expect(mapper.toKind(PointerDeviceKind.touch), PointerKind.touch);
    });

    test('maps mouse -> mouse', () {
      expect(mapper.toKind(PointerDeviceKind.mouse), PointerKind.mouse);
    });

    test('maps trackpad -> trackpad', () {
      expect(mapper.toKind(PointerDeviceKind.trackpad), PointerKind.trackpad);
    });

    test('maps unknown -> unknown', () {
      expect(mapper.toKind(PointerDeviceKind.unknown), PointerKind.unknown);
    });
  });

  group('PointerEventMapper.toSample pressure clamping', () {
    final now = DateTime.utc(2026, 4, 20);

    test('pressure > 1.0 clamps down to 1.0', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(10, 10), pressure: 1.5),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.pressure, 1.0);
    });

    test('pressure < 0.0 clamps up to 0.0', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(10, 10), pressure: -0.2),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.pressure, 0.0);
    });

    test('pressure 0.0 passes through unchanged', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(10, 10), pressure: 0.0),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.pressure, 0.0);
    });

    test('NaN pressure substitutes 0.5 neutral default', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(10, 10), pressure: double.nan),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.pressure, 0.5);
    });
  });

  group('PointerEventMapper.toSample coordinate validation', () {
    final now = DateTime.utc(2026, 4, 20);

    test('NaN dx returns null', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: Offset(double.nan, 10)),
        now,
      );
      expect(sample, isNull);
    });

    test('NaN dy returns null', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: Offset(10, double.nan)),
        now,
      );
      expect(sample, isNull);
    });

    test('infinite dx returns null', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(double.infinity, 10)),
        now,
      );
      expect(sample, isNull);
    });

    test('negative infinite dy returns null', () {
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(10, double.negativeInfinity)),
        now,
      );
      expect(sample, isNull);
    });
  });

  group('PointerEventMapper.toSample happy paths', () {
    test('maps a stylus down event to a PointerSample with timestamp', () {
      final now = DateTime.utc(2026, 4, 20);
      final sample = mapper.toSample(
        _downEvent(localPosition: const Offset(120, 340), pressure: 0.7),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.x, 120);
      expect(sample.y, 340);
      expect(sample.pressure, 0.7);
      expect(sample.kind, PointerKind.stylus);
      expect(sample.timestamp, now);
    });

    test('unknown device kind still produces a sample', () {
      final now = DateTime.utc(2026, 4, 20);
      final sample = mapper.toSample(
        _downEvent(
          localPosition: const Offset(1, 2),
          kind: PointerDeviceKind.unknown,
        ),
        now,
      );
      expect(sample, isNotNull);
      expect(sample!.kind, PointerKind.unknown);
    });
  });
}
