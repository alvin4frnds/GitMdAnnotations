import 'package:flutter/gestures.dart';

import '../../../domain/entities/pointer_sample.dart';

/// Pure mapper from Flutter's [PointerEvent] into the domain-level
/// [PointerSample]. Kept as its own class (not a free function) so the
/// widget tests can inject a seam without dragging in a port.
///
/// See IMPLEMENTATION.md §2.6 — the domain must stay Flutter-free, so
/// this mapper lives under `lib/ui/` and performs the translation at the
/// boundary.
class PointerEventMapper {
  const PointerEventMapper();

  /// Maps Flutter's [event] + a clock-supplied [now] into a domain
  /// [PointerSample].
  ///
  /// Returns `null` when the event's local coordinates are non-finite
  /// (NaN or infinity). The domain [PointerSample] rejects NaN and the
  /// annotation session depends on finite geometry for hit-test math; it
  /// is cheaper to drop the event here than to let it throw into the UI.
  ///
  /// Pressure handling:
  /// - `NaN` → substituted with `0.5` (neutral default). Some devices
  ///   report NaN when pressure is unsupported.
  /// - Values outside `[0, 1]` are clamped. Flutter documents
  ///   [PointerEvent.pressure] as normalized but real devices can report
  ///   slightly-over-1.0 values (especially when pressure is unsupported
  ///   and defaults to 1.0).
  PointerSample? toSample(PointerEvent event, DateTime now) {
    final local = event.localPosition;
    if (!local.dx.isFinite || !local.dy.isFinite) {
      return null;
    }
    final pressure = _normalizePressure(event.pressure);
    return PointerSample(
      x: local.dx,
      y: local.dy,
      pressure: pressure,
      kind: toKind(event.kind),
      timestamp: now,
    );
  }

  /// Maps Flutter's [PointerDeviceKind] to the domain [PointerKind].
  PointerKind toKind(PointerDeviceKind kind) {
    switch (kind) {
      case PointerDeviceKind.stylus:
        return PointerKind.stylus;
      case PointerDeviceKind.invertedStylus:
        return PointerKind.invertedStylus;
      case PointerDeviceKind.touch:
        return PointerKind.touch;
      case PointerDeviceKind.mouse:
        return PointerKind.mouse;
      case PointerDeviceKind.trackpad:
        return PointerKind.trackpad;
      case PointerDeviceKind.unknown:
        return PointerKind.unknown;
    }
  }

  double _normalizePressure(double raw) {
    if (raw.isNaN) {
      return 0.5;
    }
    return raw.clamp(0.0, 1.0).toDouble();
  }
}
