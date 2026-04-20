import '../../domain/ports/clock_port.dart';

/// Production [Clock] adapter. Thin wrapper over `DateTime.now()` kept behind
/// the domain port so [AnnotationSession] and other services stay testable
/// (IMPLEMENTATION.md §2.1, §2.6).
class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}
