import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/stroke_group.dart';
import 'ink_painting.dart';

/// Paints committed [StrokeGroup]s underneath an in-progress stroke fed by
/// a [ValueListenable]. The active-stroke listenable drives repaints via
/// `super(repaint: ...)`, so the painter only needs to consider static
/// configuration in [shouldRepaint].
///
/// Actual drawing is delegated to [paintStrokeGroups] in `ink_painting.dart`
/// so the offscreen `PngFlattenerAdapter` produces byte-identical output to
/// what appears on screen (IMPLEMENTATION.md §3.4, §4.5).
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

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokeGroups(
      canvas,
      groups: groups,
      activeStrokePoints: activeStroke.value,
      activeStrokeColor: activeStrokeColor,
      activeStrokeWidth: activeStrokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant InkOverlayPainter old) {
    if (old.groups.length != groups.length) return true;
    if (old.activeStrokeColor != activeStrokeColor) return true;
    if (old.activeStrokeWidth != activeStrokeWidth) return true;
    return false;
  }
}
