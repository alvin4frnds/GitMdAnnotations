import '../ports/clock_port.dart';

/// In-memory [Clock] for domain tests. Holds a mutable [DateTime] and
/// supports [advance] so tests can step the clock deterministically.
class FakeClock implements Clock {
  FakeClock(this._t);

  DateTime _t;

  @override
  DateTime now() => _t;

  /// Move the clock forward by [d]. Use to test behavior that depends on
  /// elapsed time between operations (e.g. timestamp-at-begin vs. at-end).
  void advance(Duration d) {
    _t = _t.add(d);
  }

  /// Jump to an absolute instant. Used sparingly; prefer [advance].
  void setTo(DateTime t) {
    _t = t;
  }
}
