import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'pen_tool_bar.dart';

/// Top chrome for the annotation canvas — breadcrumb, phase tag, pen tool
/// bar, undo/redo, review panel link, Submit Review button. File-private
/// to the `annotation_canvas/` folder per IMPLEMENTATION.md §2.6's
/// 200-line cap; extracted as a sibling file alongside
/// `annotation_canvas_screen.dart`.
class AnnotationTopChrome extends StatelessWidget {
  const AnnotationTopChrome({
    required this.onUndo,
    required this.onRedo,
    super.key,
  });

  /// Tapped when the user taps the undo button. The controller's `undo()`
  /// is a safe no-op on empty stacks (verified in T3 tests) — we keep the
  /// button always-enabled in T7 rather than extending `AnnotationState`
  /// just to expose stack depth. Re-evaluate when the palette / tool UI
  /// lands.
  final VoidCallback onUndo;

  /// Tapped when the user taps the redo button. Same always-enabled
  /// policy as [onUndo].
  final VoidCallback onRedo;

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
          const PenToolBar(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Undo',
            onPressed: onUndo,
            icon: Icon(Icons.undo_rounded, size: 18, color: t.textPrimary),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: onRedo,
            icon: Icon(Icons.redo_rounded, size: 18, color: t.textPrimary),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
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
