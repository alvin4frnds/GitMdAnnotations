import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
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
    required this.jobRef,
    required this.onUndo,
    required this.onRedo,
    this.onOpenReviewPanel,
    this.onSubmitReview,
    super.key,
  });

  /// Threaded through to [PenToolBar] so tapping a color dot can read
  /// the per-job [annotationControllerProvider] and dispatch `setColor`.
  final JobRef jobRef;

  /// Tapped when the user taps the undo button. The controller's `undo()`
  /// is a safe no-op on empty stacks (verified in T3 tests) — we keep the
  /// button always-enabled in T7 rather than extending `AnnotationState`
  /// just to expose stack depth. Re-evaluate when the palette / tool UI
  /// lands.
  final VoidCallback onUndo;

  /// Tapped when the user taps the redo button. Same always-enabled
  /// policy as [onUndo].
  final VoidCallback onRedo;

  /// Tapped when the user taps the "Review panel ->" link. Null leaves
  /// the link inert (fine for the mockup surface); the wired canvas
  /// screen supplies a callback that pushes `ReviewPanelScreen(jobRef:)`
  /// onto the navigator.
  final VoidCallback? onOpenReviewPanel;

  /// Tapped when the user taps the primary "Submit Review" button. Null
  /// leaves the button inert (mockup surface); the wired canvas screen
  /// supplies a callback that runs the [ReviewOrchestrator] and pushes
  /// `SubmitConfirmationScreen`.
  final VoidCallback? onSubmitReview;

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
          PenToolBar(jobRef: jobRef),
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
            onPressed: onOpenReviewPanel,
            child: Text(
              'Review panel \u2192',
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: onSubmitReview,
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
