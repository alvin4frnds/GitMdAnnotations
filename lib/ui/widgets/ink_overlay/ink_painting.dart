import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';

/// Paints the committed [groups] followed by the in-progress active stroke
/// onto [canvas]. Each committed stroke carries its own `opacity` (so the
/// highlighter tool can blend semi-transparently over text while the pen
/// stays near-opaque, per IMPLEMENTATION.md §3.4); the in-progress stroke
/// opacity is supplied by the caller via [activeStrokeOpacity].
///
/// This function is the single source of truth for ink rendering. It is
/// called both by the on-screen `InkOverlayPainter` and by the offscreen
/// `PngFlattenerAdapter`, so the PNG committed to git is byte-identical to
/// what the user saw at submit time (IMPLEMENTATION.md §3.4, §4.5).
///
/// The caller owns the [canvas] lifecycle (recorder, save/restore, clip).
/// The function does not scale, translate, or clip — it assumes the caller
/// has sized the canvas to match the logical stroke coordinate space.
///
/// **Rendering.** The pen renders as a variable-width nib: `perfect_freehand`
/// turns the sampled points into a tapered outline whose width swells where
/// the pen moved slowly and thins where it moved fast (velocity-simulated
/// pressure), and we fill that outline as a *smooth* path — every outline
/// vertex is a quadratic control point, the curve passes through the
/// midpoints — so even sparse samples on a fast stroke read as a smooth,
/// pen-like line rather than the flat, uniform-width marker the previous
/// constant-stroke renderer produced. The highlighter (a wide, chisel tool)
/// stays deliberately flat/uniform via a constant-width centreline stroke.
/// Stored `Stroke.points` are unchanged on disk — this is render-time only.
void paintStrokeGroups(
  Canvas canvas, {
  required List<StrokeGroup> groups,
  required List<Offset> activeStrokePoints,
  required Color activeStrokeColor,
  required double activeStrokeWidth,
  double activeStrokeOpacity = Stroke.kDefaultStrokeOpacity,
}) {
  for (final group in groups) {
    for (final stroke in group.strokes) {
      _paintStroke(canvas, stroke);
    }
  }
  _paintActiveStroke(
    canvas,
    points: activeStrokePoints,
    color: activeStrokeColor,
    width: activeStrokeWidth,
    opacity: activeStrokeOpacity,
  );
}

void _paintStroke(Canvas canvas, Stroke stroke) {
  if (stroke.points.isEmpty) return;
  final color = _parseHex(stroke.color).withValues(alpha: stroke.opacity);
  final points = [
    for (final p in stroke.points) PointVector(p.x, p.y, p.pressure),
  ];
  _paint(canvas, points, stroke.strokeWidth, color, isComplete: true);
}

void _paintActiveStroke(
  Canvas canvas, {
  required List<Offset> points,
  required Color color,
  required double width,
  required double opacity,
}) {
  if (points.isEmpty) return;
  // The active-stroke listenable only carries positions; velocity-simulated
  // pressure (below) derives the taper from point spacing, so a flat 0.5 here
  // is fine — `simulatePressure` ignores it. `isComplete: false` lets the
  // growing tip round off cleanly while the stroke is still being drawn.
  final vectors = [for (final p in points) PointVector(p.dx, p.dy, 0.5)];
  _paint(canvas, vectors, width, color.withValues(alpha: opacity),
      isComplete: false);
}

/// The pen nib width (2.0) and highlighter width (16.0) are far enough apart
/// that width alone tells the tools apart without threading tool identity
/// through the render layer. Anything at/above this is the flat highlighter.
const double _kHighlighterMinWidth = 8.0;

/// Base-diameter multiplier for the pen. The stored [Stroke.strokeWidth] is
/// the nominal nib width (2.0); `perfect_freehand`'s `size` is the *neutral*
/// diameter (`size = width * factor`) and pressure/velocity swell or thin it:
/// the drawn diameter ranges `size*(1-thinning)` … `size*(1+thinning)`. At
/// factor 1.7 / thinning 0.5 that is ~1.7px (fast) to ~5px (slow) — a thin
/// pen with a gentle calligraphic taper, not the heavy marker an earlier
/// bolder setting produced. Tuned by eye on-device against OneNote.
const double _kPenSizeFactor = 1.7;

void _paint(
  Canvas canvas,
  List<PointVector> points,
  double width,
  Color color, {
  required bool isComplete,
}) {
  if (points.length == 1) {
    canvas.drawCircle(points.first, width / 2, Paint()..color = color);
    return;
  }
  if (width >= _kHighlighterMinWidth) {
    _strokeFlat(canvas, points, width, color);
    return;
  }
  final outline = getStroke(
    points,
    options: StrokeOptions(
      size: width * _kPenSizeFactor,
      thinning: 0.5,
      // Keep the rendered line faithful to the raw pen path. `streamline` is a
      // low-pass filter on the input points; at the library default (0.55) it
      // lags and rounds off quick direction changes ("auto-corrects" the
      // stroke). A low value de-jitters only lightly so sharp/fast movements
      // survive, matching OneNote's gentler smoothing. `smoothing` only softens
      // the outline edges, so it can stay moderate without eating corners.
      smoothing: 0.45,
      streamline: 0.2,
      simulatePressure: true,
      isComplete: isComplete,
    ),
  );
  if (outline.isEmpty) return;
  canvas.drawPath(
    _outlineToPath(outline),
    Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true,
  );
}

/// Builds a smooth closed [Path] around the `perfect_freehand` [outline]:
/// each vertex is a quadratic control point and the curve passes through the
/// midpoint of every edge, so the filled boundary is round, never facetted.
Path _outlineToPath(List<Offset> outline) {
  final path = Path()..moveTo(outline.first.dx, outline.first.dy);
  for (var i = 0; i < outline.length; i++) {
    final p0 = outline[i];
    final p1 = outline[(i + 1) % outline.length];
    path.quadraticBezierTo(
      p0.dx,
      p0.dy,
      (p0.dx + p1.dx) / 2,
      (p0.dy + p1.dy) / 2,
    );
  }
  return path..close();
}

/// Flat, uniform-width centreline stroke for the highlighter — a Catmull-Rom
/// spline through the points so it stays smooth, stroked at the full nominal
/// [width] with round caps/joins. Deliberately *not* tapered: a chisel
/// highlighter reads as an even band, not a pen.
void _strokeFlat(
  Canvas canvas,
  List<Offset> points,
  double width,
  Color color,
) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
  } else {
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );
}

/// Parses a 7-character canonical light-mode hex (`#RRGGBB`) into a fully
/// opaque [Color]. `Stroke` has already validated the format.
Color _parseHex(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}
