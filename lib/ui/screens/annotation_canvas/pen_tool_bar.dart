import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/annotation_providers.dart';
import '../../../domain/entities/ink_tool.dart';
import '../../../domain/entities/job_ref.dart';
import '../../theme/tokens.dart';

/// Pen tool bar — interactive palette for the canvas top bar. Shows the
/// three tool icons (pan / pen / highlighter), a 5-color palette, and
/// the eraser. Tapping a color dot dispatches `setColor` on the
/// [annotationControllerProvider] for this [jobRef] — the currently
/// selected color is read back from the same provider so the UI stays
/// in sync regardless of which widget mutated it.
///
/// Palette matches PRD §5.4 FR-1.18 (5 colors, not the "6-preset"
/// phrasing used in earlier drafts): red / blue / green / amber / near-
/// black. Hex values are normalized to `#RRGGBB` so the session stores
/// a consistent format across themes.
class PenToolBar extends ConsumerWidget {
  const PenToolBar({required this.jobRef, super.key});

  final JobRef jobRef;

  static const _paletteHex = <String>[
    '#DC2626', // red
    '#2563EB', // blue
    '#059669', // green
    '#F59E0B', // amber
    '#111827', // near-black
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = ref.watch(annotationControllerProvider(jobRef));
    final selectedHex = state.color.toUpperCase();
    final controller =
        ref.read(annotationControllerProvider(jobRef).notifier);
    final panActive = !state.drawingEnabled;
    final penActive = state.drawingEnabled && state.tool == InkTool.pen;
    final hlActive =
        state.drawingEnabled && state.tool == InkTool.highlighter;
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
          _ToolIcon(
            icon: Icons.pan_tool_alt_outlined,
            active: panActive,
            activeColor: t.accentPrimary,
            onTap: () => controller.setDrawingEnabled(false),
          ),
          _ToolIcon(
            icon: Icons.edit_outlined,
            active: penActive,
            activeColor: t.accentPrimary,
            onTap: () {
              controller.setTool(InkTool.pen);
              controller.setDrawingEnabled(true);
            },
          ),
          _ToolIcon(
            icon: Icons.highlight_outlined,
            active: hlActive,
            activeColor: t.accentPrimary,
            onTap: () {
              controller.setTool(InkTool.highlighter);
              controller.setDrawingEnabled(true);
            },
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 20, color: t.borderSubtle),
          const SizedBox(width: 6),
          for (final hex in _paletteHex)
            _PenDot(
              hex: hex,
              selected: hex.toUpperCase() == selectedHex,
              onTap: () => controller.setColor(hex),
            ),
          const SizedBox(width: 6),
          Container(width: 1, height: 20, color: t.borderSubtle),
          const SizedBox(width: 2),
          // Eraser = "undo last stroke" — M1d-polish implementation.
          // Full per-stroke hit-test eraser (tap a stroke to delete it)
          // is a deferred follow-up; tapping undo-style at least gives
          // users a reversible action from the toolbar.
          _ToolIcon(
            icon: Icons.backspace_outlined,
            active: false,
            onTap: controller.undo,
          ),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? activeColor;
  final VoidCallback? onTap;
  const _ToolIcon({
    required this.icon,
    required this.active,
    this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
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
          color: active
              ? (activeColor ?? t.accentPrimary)
              : (onTap == null ? t.textMuted : t.textPrimary),
        ),
      ),
    );
  }
}

class _PenDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;
  const _PenDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 18,
          height: 18,
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
        ),
      ),
    );
  }
}
