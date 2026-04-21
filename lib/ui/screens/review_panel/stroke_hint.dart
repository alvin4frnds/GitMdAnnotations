import 'package:flutter/material.dart';

/// Faint hand-drawn hint of where a stroke sits on the source spec. Drawn
/// as a wobbly closed path so it reads as pen ink, not a geometric
/// circle. Each colour uses a different perimeter shape (seeded per
/// variant) for variety. Extracted from `review_panel_screen.dart` per
/// the §2.6 200-line cap.
class StrokeHint extends StatelessWidget {
  final Color color;
  final int variant;
  const StrokeHint({required this.color, this.variant = 0, super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 46,
        height: 46,
        child: CustomPaint(
          painter: _WobblyHintPainter(
            color: color.withValues(alpha: 0.55),
            variant: variant,
          ),
        ),
      ),
    );
  }
}

class _WobblyHintPainter extends CustomPainter {
  final Color color;
  final int variant;
  _WobblyHintPainter({required this.color, required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 4;

    // Deterministic jitter seeded by variant so each coloured hint is
    // reproducibly different but still looks hand-drawn.
    double j(int k, double amp) {
      final seed = (variant * 97 + k * 31) & 0xff;
      final n = (seed / 255.0) * 2.0 - 1.0;
      return n * amp;
    }

    final a = Offset(cx + j(0, 2), cy - r + j(1, 1.5));
    final b = Offset(cx + r + j(2, 2), cy + j(3, 2));
    final c = Offset(cx + j(4, 2), cy + r + j(5, 2));
    final d = Offset(cx - r + j(6, 1.5), cy + j(7, 2));

    final path = Path()..moveTo(a.dx, a.dy);
    path.cubicTo(
      cx + r * 0.7 + j(8, 3), cy - r * 1.05 + j(9, 3),
      cx + r * 1.05 + j(10, 3), cy - r * 0.65 + j(11, 3),
      b.dx, b.dy,
    );
    path.cubicTo(
      cx + r * 1.1 + j(12, 3), cy + r * 0.5 + j(13, 3),
      cx + r * 0.6 + j(14, 3), cy + r * 1.05 + j(15, 3),
      c.dx, c.dy,
    );
    path.cubicTo(
      cx - r * 0.5 + j(16, 3), cy + r * 1.1 + j(17, 3),
      cx - r * 1.1 + j(18, 3), cy + r * 0.6 + j(19, 3),
      d.dx, d.dy,
    );
    // Close with a deliberate overshoot so the loop doesn't land exactly on
    // the start point — reads as pen tremor.
    final closeEnd = Offset(a.dx + j(20, 2), a.dy - 2 + j(21, 1.5));
    path.cubicTo(
      cx - r * 1.05 + j(22, 3), cy - r * 0.55 + j(23, 3),
      cx - r * 0.6 + j(24, 3), cy - r * 1.05 + j(25, 3),
      closeEnd.dx, closeEnd.dy,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WobblyHintPainter old) =>
      old.color != color || old.variant != variant;
}
