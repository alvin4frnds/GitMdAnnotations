import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';

/// Paints committed [StrokeGroup]s underneath an in-progress stroke fed by
/// a [ValueListenable]. The active-stroke listenable drives repaints via
/// `super(repaint: ...)`, so the painter only needs to consider static
/// configuration in [shouldRepaint].
///
/// Paint style matches the canonical SVG rendering described in
/// IMPLEMENTATION.md §3.4 (0.9 opacity, round caps/joins, stroke style).
class InkOverlayPainter extends CustomPainter {
  InkOverlayPainter({
    required this.groups,
    required this.activeStroke,
    required this.activeStrokeColor,
    required this.activeStrokeWidth,
  }) : super(repaint: activeStroke);

  final List<StrokeGroup> groups;
  final ValueListenable<List<Offset>> activeStroke;
  final Color activeStrokeColor;
  final double activeStrokeWidth;

  /// SVG fidelity constant (§3.4 — `opacity="0.9"`).
  static const double _strokeOpacity = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    for (final group in groups) {
      for (final stroke in group.strokes) {
        _paintStroke(canvas, stroke);
      }
    }
    _paintActiveStroke(canvas);
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) {
      return;
    }
    final paint = _buildPaint(
      color: _parseHex(stroke.color),
      width: stroke.strokeWidth,
    );
    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      canvas.drawCircle(Offset(p.x, p.y), stroke.strokeWidth, paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (var i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].x, stroke.points[i].y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintActiveStroke(Canvas canvas) {
    final points = activeStroke.value;
    if (points.isEmpty) {
      return;
    }
    final paint = _buildPaint(
      color: activeStrokeColor,
      width: activeStrokeWidth,
    );
    if (points.length == 1) {
      canvas.drawCircle(
        points.first,
        activeStrokeWidth,
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

  Paint _buildPaint({required Color color, required double width}) {
    return Paint()
      ..color = color.withValues(alpha: _strokeOpacity)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
  }

  /// Parses a 7-character canonical light-mode hex (`#RRGGBB`) into a
  /// fully opaque [Color]. `Stroke` has already validated the format.
  Color _parseHex(String hex) {
    final value = int.parse(hex.substring(1), radix: 16);
    return Color(0xFF000000 | value);
  }

  @override
  bool shouldRepaint(covariant InkOverlayPainter old) {
    if (old.groups.length != groups.length) return true;
    if (old.activeStrokeColor != activeStrokeColor) return true;
    if (old.activeStrokeWidth != activeStrokeWidth) return true;
    return false;
  }
}
