/// Logical-pixel dimensions of an annotation canvas. Domain-level replacement
/// for Flutter's `Size` (`dart:ui`), which cannot be imported into
/// `lib/domain/**` per IMPLEMENTATION.md §2.6.
///
/// Both dimensions must be positive and finite. Zero, negative, NaN, and
/// infinite values are rejected with [ArgumentError] at construction, mirroring
/// the validation pattern on `StrokePoint` / `PointerSample`.
class CanvasSize {
  CanvasSize({required this.width, required this.height}) {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError.value(
        width,
        'width',
        'must be a finite value > 0',
      );
    }
    if (!height.isFinite || height <= 0) {
      throw ArgumentError.value(
        height,
        'height',
        'must be a finite value > 0',
      );
    }
  }

  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CanvasSize(${width}x$height)';
}
