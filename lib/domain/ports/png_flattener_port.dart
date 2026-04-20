import 'dart:typed_data';

import '../entities/canvas_size.dart';
import '../entities/stroke_group.dart';

/// Renders a list of [StrokeGroup]s onto a transparent canvas of a given
/// logical size and returns a PNG byte stream.
///
/// The image is the same logical size as [CanvasSize]; the adapter picks
/// the device pixel ratio — a logical-size guarantee is all the review
/// pipeline needs because the SVG carries the vector truth
/// (IMPLEMENTATION.md §4.5).
///
/// Pure-function contract: same groups + same canvas → byte-identical
/// output. The real adapter (T10) must honor this for the review-commit
/// determinism invariant documented in IMPLEMENTATION.md §3.7.
///
/// Implementations throw [PngFlattenError] (sealed) on failure; callers
/// switch exhaustively over the two subtypes to map to UI error states.
abstract class PngFlattener {
  Future<Uint8List> flatten({
    required List<StrokeGroup> groups,
    required CanvasSize canvas,
  });
}

/// Sealed failure type for [PngFlattener] implementations.
///
/// Fake implementations (`FakePngFlattener`) never throw — the sealed
/// type exists for the real adapter (`PngFlattenerAdapter`, T10). Review
/// submission catches this at the boundary and maps it through
/// `ErrorPresenter` (IMPLEMENTATION.md §2.3).
sealed class PngFlattenError implements Exception {
  const PngFlattenError(this.message);

  final String message;

  @override
  String toString() => 'PngFlattenError($message)';
}

/// Raised when `Picture.toImage` fails — usually allocation or rendering
/// failure on the engine side.
class PngFlattenRenderError extends PngFlattenError {
  const PngFlattenRenderError(super.message);
}

/// Raised when `Image.toByteData(format: png)` returns null or otherwise
/// fails to encode the image to PNG bytes.
class PngFlattenEncodeError extends PngFlattenError {
  const PngFlattenEncodeError(super.message);
}
