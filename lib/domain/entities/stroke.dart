/// A single sampled point along a pen stroke: logical canvas coordinates
/// plus normalized pressure in `[0, 1]` captured from the stylus.
///
/// `x` and `y` may be negative and may be `double.infinity` /
/// `double.negativeInfinity`; coordinate clamping for rendering is handled
/// at the render layer, not at this value object. `x`, `y`, and `pressure`
/// are rejected as `NaN` because equality and hashing break on `NaN`.
class StrokePoint {
  StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokePoint &&
          other.x == x &&
          other.y == y &&
          other.pressure == pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);

  @override
  String toString() => 'StrokePoint($x, $y, p=$pressure)';
}

/// One polyline captured between pointer-down and pointer-up. `color` is the
/// canonical light-mode hex stored in SVG (IMPLEMENTATION.md §3.4); dark-mode
/// rendering is handled by `InkColorAdapter` at display time, never persisted.
class Stroke {
  Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  }) {
    if (!_colorPattern.hasMatch(color)) {
      throw ArgumentError.value(
        color,
        'color',
        'must match ${_colorPattern.pattern} (canonical light-mode hex)',
      );
    }
  }

  final List<StrokePoint> points;
  final String color;
  final double strokeWidth;

  static final RegExp _colorPattern = RegExp(r'^#[0-9A-F]{6}$', caseSensitive: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Stroke) return false;
    if (other.color != color) return false;
    if (other.strokeWidth != strokeWidth) return false;
    if (other.points.length != points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(color, strokeWidth, Object.hashAll(points));

  @override
  String toString() =>
      'Stroke(color: $color, width: $strokeWidth, points: ${points.length})';
}
