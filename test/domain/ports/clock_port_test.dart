import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_clock.dart';

/// Contract test for the [Clock] port implemented by [FakeClock].
/// See IMPLEMENTATION.md §4.5. A real `SystemClock` wrapping `DateTime.now`
/// lives in the infra layer; domain code never imports it.
void main() {
  group('FakeClock', () {
    test('now() returns the preset DateTime', () {
      final clock = FakeClock(DateTime.utc(2026, 4, 20, 9, 14, 22));
      expect(clock.now(), DateTime.utc(2026, 4, 20, 9, 14, 22));
    });

    test('advance(d) moves the clock forward by the given duration', () {
      final clock = FakeClock(DateTime.utc(2026, 4, 20, 9, 14, 22));
      clock.advance(const Duration(seconds: 5));
      expect(clock.now(), DateTime.utc(2026, 4, 20, 9, 14, 27));
    });

    test('now() is idempotent (two reads without advance return same value)',
        () {
      final clock = FakeClock(DateTime.utc(2026, 4, 20, 9, 14, 22));
      final a = clock.now();
      final b = clock.now();
      expect(a, b);
    });
  });
}
