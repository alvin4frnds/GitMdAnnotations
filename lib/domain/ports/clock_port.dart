/// Abstract clock boundary used by domain services that need wall time —
/// e.g. [AnnotationSession] stamping a stroke group at pointer-down.
///
/// The real `SystemClock` lives in `lib/infra/clock/`; tests override with
/// `FakeClock`. Keeps `DateTime.now()` out of the domain (IMPLEMENTATION.md
/// §2.6).
abstract class Clock {
  DateTime now();
}
