/// Domain-level pointer kinds. The UI layer maps Flutter's
/// `PointerDeviceKind` into this enum at the annotation-session seam so that
/// `lib/domain/**` stays Flutter-free (IMPLEMENTATION.md §2.6).
///
/// Only [stylus] creates strokes in Milestone 1b T3. [invertedStylus] is
/// reserved for future eraser-mode routing and is ignored (silent no-op)
/// for now. [touch], [mouse], [trackpad], and [unknown] are ignored too —
/// palm rejection per PRD §5.4 FR-1.16 / FR-1.17.
enum PointerKind {
  stylus,
  invertedStylus,
  touch,
  mouse,
  trackpad,
  unknown,
}

/// A single pointer sample — logical canvas coordinates, normalized
/// pressure in `[0, 1]`, the pointer kind, and a sample timestamp.
///
/// Mirrors the validation surface of [StrokePoint] from T1: `x`, `y`, and
/// `pressure` reject `NaN`; `pressure` is additionally constrained to the
/// `[0, 1]` interval. `x` / `y` may be negative or infinite — canvas
/// clipping is a render-layer concern.
class PointerSample {
  PointerSample({
    required this.x,
    required this.y,
    required this.pressure,
    required this.kind,
    required this.timestamp,
  }) {
    if (x.isNaN) {
      throw ArgumentError.value(x, 'x', 'must not be NaN');
    }
    if (y.isNaN) {
      throw ArgumentError.value(y, 'y', 'must not be NaN');
    }
    if (pressure.isNaN || pressure < 0.0 || pressure > 1.0) {
      throw ArgumentError.value(
        pressure,
        'pressure',
        'must be a normalized value in [0, 1]',
      );
    }
  }

  final double x;
  final double y;
  final double pressure;
  final PointerKind kind;
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointerSample &&
          other.x == x &&
          other.y == y &&
          other.pressure == pressure &&
          other.kind == kind &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(x, y, pressure, kind, timestamp);

  @override
  String toString() =>
      'PointerSample($x, $y, p=$pressure, kind=$kind, ts=$timestamp)';
}
