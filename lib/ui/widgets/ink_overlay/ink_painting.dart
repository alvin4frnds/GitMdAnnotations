import 'package:flutter/material.dart';

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
/// **Rendering.** We draw a smooth [Catmull-Rom] spline **through the actual
/// captured points**, stroked at the full nominal width with round caps and
/// joins. The spline passes through every sampled point (so the ink is
/// faithful to what the pen drew) but curves between them, so sparse samples
/// on a fast stroke read as a smooth line rather than straight facets. This
/// is deliberately NOT `perfect_freehand`'s tapered-outline fill: resampling
/// the points into a coarse outline is what made fast strokes look
/// facetted/"rough", and smoothing that outline through its midpoints
/// pinched thin strokes until handwriting became illegible. A stroked
/// centerline keeps every stroke full-width and legible. Stored
/// `Stroke.points` are unchanged on disk — this is render-time only.
///
/// [Catmull-Rom]: https://en.wikipedia.org/wiki/Centripetal_Catmull%E2%80%93Rom_spline
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
  _strokeSmooth(
    canvas,
    [for (final p in stroke.points) Offset(p.x, p.y)],
    stroke.strokeWidth,
    color,
  );
}

void _paintActiveStroke(
  Canvas canvas, {
  required List<Offset> points,
  required Color color,
  required double width,
  required double opacity,
}) {
  if (points.isEmpty) return;
  _strokeSmooth(canvas, points, width, color.withValues(alpha: opacity));
}

/// Strokes a smooth Catmull-Rom spline through [points] at [width] in
/// [color]. A single point renders as a dot the same thickness as the line;
/// two points render as a straight segment. Round caps/joins keep the ends
/// and any true corner clean.
void _strokeSmooth(
  Canvas canvas,
  List<Offset> points,
  double width,
  Color color,
) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    canvas.drawCircle(points.first, width / 2, Paint()..color = color);
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
  } else {
    // Catmull-Rom → cubic bezier: the tangent at each point is 1/6 of the
    // vector between its neighbours (standard tension). The curve interpolates
    // every point, so it stays faithful to the stroke while rounding the gaps
    // between sparse samples. Ends clamp to themselves (no phantom neighbour).
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
