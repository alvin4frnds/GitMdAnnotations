import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Pen tool bar — display-only chrome for the canvas top bar. Shows the
/// mockup's "red pen selected" visual (pan / pen / highlighter icons + 5
/// color dots + eraser). Palette wiring is a later task — T7 hardcodes
/// the active stroke color to `context.tokens.inkRed` in the screen.
class PenToolBar extends StatelessWidget {
  const PenToolBar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
