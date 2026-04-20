import '../../domain/ports/clock_port.dart';

/// Real [Clock] backed by `DateTime.now()`. The only place in the tree that
/// reads wall time; domain code receives it through [Clock] and is therefore
/// test-deterministic (IMPLEMENTATION.md §2.3, §4.5).
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
