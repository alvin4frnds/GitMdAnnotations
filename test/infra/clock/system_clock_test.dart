import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/ports/clock_port.dart';
import 'package:gitmdannotations_tablet/infra/clock/system_clock.dart';

void main() {
  group('SystemClock', () {
    test('implements Clock port', () {
      expect(SystemClock(), isA<Clock>());
    });

    test('now() returns monotonic non-decreasing DateTime values', () async {
      final clock = SystemClock();
      final first = clock.now();
      // Wait a millisecond so the clock has a chance to advance on the
      // coarsest platforms; the assertion is >= to tolerate identical ticks.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final second = clock.now();
      expect(second.isBefore(first), isFalse);
    });
  });
}
