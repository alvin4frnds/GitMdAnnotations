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
/// **Smoothing.** Strokes are rendered through `perfect_freehand` which
/// turns the sampled pointer points into a tapered, pressure-aware
/// outline polygon and fills it. This eliminates the polygonal `lineTo`
/// look that bare canvas paths produce on fast strokes (e.g. a quickly
/// drawn circle showed visible straight edges before this change).
/// Stored `Stroke.points` are unchanged on disk — smoothing is render-
/// time-only.
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
  if (stroke.points.length == 1) {
    final p = stroke.points.first;
    canvas.drawCircle(
      Offset(p.x, p.y),
      stroke.strokeWidth,
      Paint()..color = color,
    );
    return;
  }
  final outline = getStroke(
    [
      for (final p in stroke.points) PointVector(p.x, p.y, p.pressure),
    ],
    options: StrokeOptions(
      size: stroke.strokeWidth,
      // Stored strokes already carry the digitizer's pressure samples,
      // so `simulatePressure: false` consumes them as-is. The submit-
      // time PNG/PDF flatten and the on-screen render share this
      // function, so both surfaces taper identically.
      simulatePressure: false,
      isComplete: true,
    ),
  );
  _fillOutline(canvas, outline, color);
}

void _paintActiveStroke(
  Canvas canvas, {
  required List<Offset> points,
  required Color color,
  required double width,
  required double opacity,
}) {
  if (points.isEmpty) return;
  final paintColor = color.withValues(alpha: opacity);
  if (points.length == 1) {
    canvas.drawCircle(points.first, width, Paint()..color = paintColor);
    return;
  }
  final outline = getStroke(
    [
      for (final p in points) PointVector(p.dx, p.dy),
    ],
    options: StrokeOptions(
      size: width,
      // Active stroke has no pressure samples (the listener buffers
      // Offsets only), so let perfect_freehand simulate pressure from
      // velocity. `isComplete: false` leaves the trailing tail un-
      // capped so the in-flight stroke doesn't visibly snap each frame.
      simulatePressure: true,
      isComplete: false,
    ),
  );
  _fillOutline(canvas, outline, paintColor);
}

/// Fills the closed [outline] polygon produced by `getStroke`. The
/// outline already encodes the stroke's tapered edges; a plain fill is
/// the right paint mode (no `strokeWidth` needed).
void _fillOutline(Canvas canvas, List<Offset> outline, Color color) {
  if (outline.isEmpty) return;
  final path = Path()..moveTo(outline.first.dx, outline.first.dy);
  for (var i = 1; i < outline.length; i++) {
    path.lineTo(outline[i].dx, outline[i].dy);
  }
  path.close();
  canvas.drawPath(path, Paint()..color = color);
}

/// Parses a 7-character canonical light-mode hex (`#RRGGBB`) into a fully
/// opaque [Color]. `Stroke` has already validated the format.
Color _parseHex(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}
