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
abstract class PngFlattener {
  Future<Uint8List> flatten({
    required List<StrokeGroup> groups,
    required CanvasSize canvas,
  });
}
