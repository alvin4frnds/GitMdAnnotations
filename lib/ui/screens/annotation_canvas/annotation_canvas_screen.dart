import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Screen 5 from the mockups — pen annotation overlay.
///
/// UI-spike only: strokes are hard-coded, no pen input, no state.
class AnnotationCanvasScreen extends StatelessWidget {
  const AnnotationCanvasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceBackground,
      child: Column(
        children: [
          const _TopChrome(),
          Container(height: 1, color: t.borderSubtle),
          const Expanded(child: _Body()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top chrome — pen tool bar with pen tool selected + 5 pen colors + eraser.
// ---------------------------------------------------------------------------

class _TopChrome extends StatelessWidget {
  const _TopChrome();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '\u2190 jobs',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Text(
            'spec-auth-flow-totp',
            style: appMono(context, size: 13, weight: FontWeight.w500),
          ),
          const SizedBox(width: 10),
          _PhaseTag(label: 'Awaiting review'),
          const Spacer(),
          const _PenToolBar(),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () {},
            child: Text(
              'Review panel \u2192',
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Submit Review'),
          ),
        ],
      ),
    );
  }
}

class _PhaseTag extends StatelessWidget {
  final String label;
  const _PhaseTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.accentPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PenToolBar extends StatelessWidget {
  const _PenToolBar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Pen tool bar is SELECTED (outer border + soft bg).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.accentPrimary, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolIcon(icon: Icons.pan_tool_alt_outlined, active: false),
          _ToolIcon(
            icon: Icons.edit_outlined,
            active: true,
            activeColor: t.accentPrimary,
          ),
          _ToolIcon(icon: Icons.highlight_outlined, active: false),
          const SizedBox(width: 4),
          Container(width: 1, height: 20, color: t.borderSubtle),
          const SizedBox(width: 6),
          _PenDot(color: t.inkRed, selected: true),
          _PenDot(color: t.inkBlue),
          _PenDot(color: t.inkGreen),
          const _PenDot(color: Color(0xFFF59E0B)),
          _PenDot(color: t.textPrimary),
          const SizedBox(width: 6),
          Container(width: 1, height: 20, color: t.borderSubtle),
          const SizedBox(width: 2),
          _ToolIcon(icon: Icons.backspace_outlined, active: false),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? activeColor;
  const _ToolIcon({required this.icon, required this.active, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? (activeColor ?? t.accentPrimary).withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: 16,
        color: active ? (activeColor ?? t.accentPrimary) : t.textMuted,
      ),
    );
  }
}

class _PenDot extends StatelessWidget {
  final Color color;
  final bool selected;
  const _PenDot({required this.color, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: t.surfaceElevated, width: 2)
            : null,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: color,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — left rail + main content with CustomPaint overlay + margin notes.
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LeftRail(),
        Container(width: 1, color: t.borderSubtle),
        const Expanded(child: _MainContent()),
      ],
    );
  }
}

class _LeftRail extends StatelessWidget {
  const _LeftRail();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 200,
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailHeader(label: 'On this page'),
          const SizedBox(height: 8),
          _RailItem(label: 'Goals'),
          _RailItem(label: 'Non-goals'),
          _RailItem(label: 'Open questions', active: true),
          _RailItem(label: 'File-level change plan'),
          _RailItem(label: 'Assumptions'),
          _RailItem(label: 'Changelog', muted: true),
          const SizedBox(height: 20),
          Container(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          _RailHeader(label: 'Ink layers'),
          const SizedBox(height: 8),
          _InkLayerItem(color: t.inkRed, label: 'Group A \u2014 line 47'),
          _InkLayerItem(color: t.inkBlue, label: 'Group B \u2014 line 23'),
          _InkLayerItem(color: t.inkGreen, label: 'Group C \u2014 line 89'),
        ],
      ),
    );
  }
}

class _RailHeader extends StatelessWidget {
  final String label;
  const _RailHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final bool active;
  final bool muted;
  const _RailItem({
    required this.label,
    this.active = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active
        ? t.accentPrimary
        : muted
            ? t.textMuted.withValues(alpha: 0.7)
            : t.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _InkLayerItem extends StatelessWidget {
  final Color color;
  final String label;
  const _InkLayerItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main content — markdown stub + CustomPaint ink overlay + margin notes.
// ---------------------------------------------------------------------------

class _MainContent extends StatelessWidget {
  const _MainContent();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Rendered markdown stub.
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: _MarkdownStub(),
            ),
          ),
          // Transparent ink overlay.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _InkOverlayPainter(
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

class _MarkdownStub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    TextStyle h1 = TextStyle(
      color: t.textPrimary,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
    TextStyle h2 = TextStyle(
      color: t.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    TextStyle body = TextStyle(
      color: t.textPrimary,
      fontSize: 14,
      height: 1.7,
    );
    TextStyle meta = TextStyle(color: t.textMuted, fontSize: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Auth flow \u2014 TOTP rollout', style: h1),
        const SizedBox(height: 6),
        Text('Generated by Claude Code on 2026-04-19', style: meta),
        const SizedBox(height: 20),
        Text('Open questions', style: h2),
        const SizedBox(height: 8),
        Text(
          'Q1: Should auth flow support magic links as primary, or only as '
          'fallback after TOTP?',
          style: body,
        ),
        Text(
          'Q2: Do we expire the session-cookie grace period at 7 or 14 days?',
          style: body,
        ),
        Text(
          'Q3: Session store \u2014 assume Redis, or read from config?',
          style: body,
        ),
        Text(
          'Q4: Do we rate-limit TOTP attempts per account or per IP?',
          style: body,
        ),
        const SizedBox(height: 20),
        Text('Assumptions', style: h2),
        const SizedBox(height: 8),
        Text('Default session store will remain Redis.', style: body),
        Text(
          'TOTP apps supported: Google Authenticator, 1Password, Authy.',
          style: body,
        ),
        Text(
          'Migration is transparent; no user-visible downtime.',
          style: body,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter — three hard-coded stroke groups.
// Coordinates are in the main-content local coordinate space.
// ---------------------------------------------------------------------------

class _InkOverlayPainter extends CustomPainter {
  final Color red;
  final Color blue;
  final Color green;

  const _InkOverlayPainter({
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

    // Four Bezier arcs approximating a wobbly circle.
    final path = Path()
      ..moveTo(cx + r, cy)
      ..cubicTo(
        cx + r, cy + r * 0.6,
        cx + r * 0.5, cy + r * 1.05,
        cx, cy + r,
      )
      ..cubicTo(
        cx - r * 0.55, cy + r * 1.05,
        cx - r * 1.05, cy + r * 0.45,
        cx - r, cy,
      )
      ..cubicTo(
        cx - r * 1.05, cy - r * 0.55,
        cx - r * 0.45, cy - r * 1.05,
        cx, cy - r,
      )
      ..cubicTo(
        cx + r * 0.55, cy - r * 1.05,
        cx + r * 1.05, cy - r * 0.55,
        cx + r, cy,
      );

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

    // Arrowhead — two short lines at the tip.
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final angle = math.atan2(dy, dx);
    const headLen = 14.0;
    const headSpread = 0.5; // radians

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

    // Corners, each nudged slightly for hand-drawn feel.
    const tl = Offset(182, 541);
    const tr = Offset(361, 538);
    const br = Offset(358, 621);
    const bl = Offset(179, 618);

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      // top edge with a tiny mid-jitter
      ..quadraticBezierTo(270, 536, tr.dx, tr.dy)
      // right edge
      ..quadraticBezierTo(363, 580, br.dx, br.dy)
      // bottom edge
      ..quadraticBezierTo(270, 624, bl.dx, bl.dy)
      // left edge back to start
      ..quadraticBezierTo(177, 580, tl.dx, tl.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkOverlayPainter old) =>
      old.red != red || old.blue != blue || old.green != green;
}
