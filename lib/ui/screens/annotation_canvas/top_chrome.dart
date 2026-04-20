import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Top chrome for the annotation canvas — breadcrumb, phase tag, pen tool
/// bar, review panel link, Submit Review button. File-private to the
/// `annotation_canvas/` folder per IMPLEMENTATION.md §2.6's 200-line cap;
/// extracted as a sibling file alongside `annotation_canvas_screen.dart`.
class AnnotationTopChrome extends StatelessWidget {
  const AnnotationTopChrome({super.key});

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
          const _PhaseTag(label: 'Awaiting review'),
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
    // Pen tool bar is visually SELECTED (outer border + soft bg). Palette
    // wiring is a follow-up task — the mockup's "red pen selected" look is
    // preserved here as display chrome only.
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
          const _ToolIcon(icon: Icons.pan_tool_alt_outlined, active: false),
          _ToolIcon(
            icon: Icons.edit_outlined,
            active: true,
            activeColor: t.accentPrimary,
          ),
          const _ToolIcon(icon: Icons.highlight_outlined, active: false),
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
          const _ToolIcon(icon: Icons.backspace_outlined, active: false),
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
