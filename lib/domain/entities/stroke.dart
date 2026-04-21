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
///
/// [opacity] is per-stroke so the highlighter tool can commit a semi-transparent
/// line while the pen stays near-opaque. `AnnotationSession._commit` sets it
/// via `_opacityFor(tool)`; the SVG serializer emits it as the `opacity="…"`
/// attribute; the paint layer mixes it into the final `Color.withValues`.
class Stroke {
  Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.opacity = kDefaultStrokeOpacity,
  }) {
    if (!_colorPattern.hasMatch(color)) {
      throw ArgumentError.value(
        color,
        'color',
        'must match ${_colorPattern.pattern} (canonical light-mode hex)',
      );
    }
    if (opacity.isNaN || opacity < 0.0 || opacity > 1.0) {
      throw ArgumentError.value(
        opacity,
        'opacity',
        'must be a normalized value in [0, 1]',
      );
    }
  }

  /// Default opacity matches the pen tool and the legacy global paint value
  /// (IMPLEMENTATION.md §3.4 `opacity="0.9"`). Highlighter overrides to a
  /// lower value at `AnnotationSession._commit` time.
  static const double kDefaultStrokeOpacity = 0.9;

  final List<StrokePoint> points;
  final String color;
  final double strokeWidth;

  /// Normalized alpha in `[0, 1]`. Emitted into the SVG `opacity` attribute
  /// verbatim and applied as `Color.withValues(alpha: opacity)` at paint time.
  final double opacity;

  static final RegExp _colorPattern = RegExp(r'^#[0-9A-F]{6}$', caseSensitive: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Stroke) return false;
    if (other.color != color) return false;
    if (other.strokeWidth != strokeWidth) return false;
    if (other.opacity != opacity) return false;
    if (other.points.length != points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(color, strokeWidth, opacity, Object.hashAll(points));

  @override
  String toString() =>
      'Stroke(color: $color, width: $strokeWidth, opacity: $opacity, '
      'points: ${points.length})';
}
