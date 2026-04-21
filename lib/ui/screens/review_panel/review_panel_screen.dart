import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/job_ref.dart';
import '../../../domain/services/open_question_extractor.dart';
import '../../theme/tokens.dart';
import 'chrome_bar.dart';
import 'markdown_pane.dart';
import 'typed_review_pane.dart';

/// Review panel — Screen 6 of the M1a mockups, T7-wired to
/// [reviewControllerProvider].
///
/// Split-pane layout: left 1fr annotated markdown (with faint ink-stroke
/// hints at three anchor points), right 420 px typed review panel on a
/// sunken surface. Top chrome mirrors the shell style: mono breadcrumb
/// left, live auto-save caption mid-right, primary Submit button far
/// right.
///
/// PDF-source jobs flow through the same panel: the open questions list
/// arrives empty and the right pane renders only the free-form notes
/// section. PDF Submit is routed through the PDF annotation surface in
/// a future milestone — the Submit button here currently triggers
/// markdown-path composition inside [ReviewController.submit] when the
/// caller supplies a markdown [SpecFile].
class ReviewPanelScreen extends ConsumerWidget {
  const ReviewPanelScreen({
    required this.jobRef,
    this.questions = const <OpenQuestion>[],
    this.onSubmitTap,
    super.key,
  });

  final JobRef jobRef;
  final List<OpenQuestion> questions;

  /// Fired when the user taps "Submit review" in the chrome. The caller
  /// typically pushes a [SubmitConfirmationScreen] onto the navigator to
  /// preview and confirm the planned writes.
  final VoidCallback? onSubmitTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        children: [
          ReviewChromeBar(
            jobRef: jobRef,
            onSubmit: onSubmitTap ?? () {},
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: MarkdownPane()),
                SizedBox(
                  width: 420,
                  child: TypedReviewPane(
                    jobRef: jobRef,
                    questions: questions,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
