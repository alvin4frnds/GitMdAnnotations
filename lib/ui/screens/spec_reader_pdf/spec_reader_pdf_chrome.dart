import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../annotation_canvas/pen_tool_bar.dart';

/// Top chrome for the PDF spec reader. Visually identical to the
/// markdown variant (`spec_reader_md_screen.dart`'s top bar) so the two
/// readers feel like the same screen with different content panes.
class SpecReaderPdfChrome extends StatelessWidget {
  const SpecReaderPdfChrome({
    required this.jobId,
    required this.onUndo,
    required this.onRedo,
    super.key,
  });

  final String jobId;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text('\u2190 jobs',
              style: TextStyle(color: t.textMuted, fontSize: 13)),
          const SizedBox(width: 12),
          Text(
            jobId,
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
