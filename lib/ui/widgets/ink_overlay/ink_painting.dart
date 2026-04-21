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
  if (stroke.points.isEmpty) {
    return;
  }
  final paint = _buildPaint(
    color: _parseHex(stroke.color),
    width: stroke.strokeWidth,
    opacity: stroke.opacity,
  );
  if (stroke.points.length == 1) {
    final p = stroke.points.first;
    canvas.drawCircle(
      Offset(p.x, p.y),
      stroke.strokeWidth,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
  for (var i = 1; i < stroke.points.length; i++) {
    path.lineTo(stroke.points[i].x, stroke.points[i].y);
  }
  canvas.drawPath(path, paint);
}

void _paintActiveStroke(
  Canvas canvas, {
  required List<Offset> points,
  required Color color,
  required double width,
  required double opacity,
}) {
  if (points.isEmpty) {
    return;
  }
  final paint = _buildPaint(color: color, width: width, opacity: opacity);
  if (points.length == 1) {
    canvas.drawCircle(
      points.first,
      width,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx, points[i].dy);
  }
  canvas.drawPath(path, paint);
}

Paint _buildPaint({
  required Color color,
  required double width,
  required double opacity,
}) {
  return Paint()
    ..color = color.withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
}

/// Parses a 7-character canonical light-mode hex (`#RRGGBB`) into a fully
/// opaque [Color]. `Stroke` has already validated the format.
Color _parseHex(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}
