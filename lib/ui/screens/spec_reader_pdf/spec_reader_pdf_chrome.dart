import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../annotation_canvas/pen_tool_bar.dart';

/// Top chrome for the PDF spec reader. Visually identical to the
/// markdown variant (`spec_reader_md_screen.dart`'s top bar) so the two
/// readers feel like the same screen with different content panes.
class SpecReaderPdfChrome extends StatelessWidget {
  const SpecReaderPdfChrome({
    required this.jobRef,
    required this.jobId,
    required this.onUndo,
    required this.onRedo,
    required this.onOpenReviewPanel,
    required this.onSubmit,
    super.key,
  });

  /// Null when opened via the repo browser \u2014 in that case the pen tool
  /// bar, undo/redo, Review panel, and Submit buttons are hidden.
  final JobRef? jobRef;
  final String jobId;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onOpenReviewPanel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final job = jobRef;
    return Container(
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                job == null ? '\u2190 back' : '\u2190 jobs',
                style: TextStyle(color: t.textMuted, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            jobId,
            style: appMono(context, size: 13, weight: FontWeight.w500),
          ),
          if (job != null) ...[
            const SizedBox(width: 10),
            const _PhaseTag(label: 'Awaiting review'),
          ],
          const Spacer(),
          if (job != null) ...[
            PenToolBar(jobRef: job),
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
              onPressed: onSubmit,
              child: const Text('Submit Review'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhaseTag extends StatelessWidget {
  const _PhaseTag({required this.label});
  final String label;

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
