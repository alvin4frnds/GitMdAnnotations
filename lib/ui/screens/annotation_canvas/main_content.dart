import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'markdown_stub.dart';

/// Main-content area behind the ink overlay. Pre-T7 behavior preserved as
/// the "legacy" variant below (hardcoded painter + margin notes); the T7
/// wiring replaces those with live controller state in a follow-up commit.
///
/// This file stays behind the 200-line cap by extracting the `_InkOverlay…`
/// painter and margin notes into a single widget — keeping the split
/// pure-refactor for the first commit.
class AnnotationMainContent extends StatelessWidget {
  const AnnotationMainContent({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Rendered markdown stub.
          const Padding(
            padding: EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: MarkdownStub(),
            ),
          ),
          // Transparent ink overlay (legacy mockup painter).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LegacyInkOverlayPainter(
                  red: t.inkRed,
                  blue: t.inkBlue,
                  green: t.inkGreen,
                ),
              ),
            ),
          ),
          // Margin note near Group A (top-left circle).
          Positioned(
            left: 300,
            top: 140,
            child: Transform.rotate(
              angle: -3 * math.pi / 180,
              child: Text(
                'TOTP first.\nfallback only.',
                style: appHandwriting(context, size: 20, color: t.inkRed),
              ),
            ),
          ),
          // Margin note near Group C (bottom rectangle).
          Positioned(
            left: 560,
            top: 560,
            child: Transform.rotate(
              angle: 2 * math.pi / 180,
              child: Text(
                '14 \u2014 match refresh token',
                style: appHandwriting(context, size: 20, color: t.inkRed),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legacy painter — three hardcoded stroke groups (mockup visuals only).
// Removed in the T7 wiring commit and replaced with `InkOverlay`.
// ---------------------------------------------------------------------------

class _LegacyInkOverlayPainter extends CustomPainter {
  final Color red;
  final Color blue;
  final Color green;

  const _LegacyInkOverlayPainter({
    required this.red,
    required this.blue,
    required this.green,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintGroupA(canvas);
    _paintGroupB(canvas);
    _paintGroupC(canvas);
  }

  // Group A — rough hand-drawn circle around (250, 180), radius ~40.
  void _paintGroupA(Canvas canvas) {
    final paint = Paint()
      ..color = red.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const cx = 250.0;
    const cy = 180.0;
    const r = 40.0;

    final path = Path()
      ..moveTo(cx + r, cy)
      ..cubicTo(cx + r, cy + r * 0.6, cx + r * 0.5, cy + r * 1.05, cx, cy + r)
      ..cubicTo(
          cx - r * 0.55, cy + r * 1.05, cx - r * 1.05, cy + r * 0.45, cx - r, cy)
      ..cubicTo(
          cx - r * 1.05, cy - r * 0.55, cx - r * 0.45, cy - r * 1.05, cx, cy - r)
      ..cubicTo(
          cx + r * 0.55, cy - r * 1.05, cx + r * 1.05, cy - r * 0.55, cx + r, cy);

    canvas.drawPath(path, paint);
  }

  // Group B — arrow from (120, 360) to (300, 420) with arrowhead.
  void _paintGroupB(Canvas canvas) {
    final paint = Paint()
      ..color = blue.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const start = Offset(120, 360);
    const end = Offset(300, 420);
    canvas.drawLine(start, end, paint);

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final angle = math.atan2(dy, dx);
    const headLen = 14.0;
    const headSpread = 0.5;

    final h1 = Offset(
      end.dx - headLen * math.cos(angle - headSpread),
      end.dy - headLen * math.sin(angle - headSpread),
    );
    final h2 = Offset(
      end.dx - headLen * math.cos(angle + headSpread),
      end.dy - headLen * math.sin(angle + headSpread),
    );
    canvas.drawLine(end, h1, paint);
    canvas.drawLine(end, h2, paint);
  }

  // Group C — wobbly rectangle, corners roughly (180, 540) to (360, 620).
  void _paintGroupC(Canvas canvas) {
    final paint = Paint()
      ..color = green.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const tl = Offset(182, 541);
    const tr = Offset(361, 538);
    const br = Offset(358, 621);
    const bl = Offset(179, 618);

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..quadraticBezierTo(270, 536, tr.dx, tr.dy)
      ..quadraticBezierTo(363, 580, br.dx, br.dy)
      ..quadraticBezierTo(270, 624, bl.dx, bl.dy)
      ..quadraticBezierTo(177, 580, tl.dx, tl.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LegacyInkOverlayPainter old) =>
      old.red != red || old.blue != blue || old.green != green;
}
