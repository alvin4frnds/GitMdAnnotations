import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/controllers/review_orchestrator.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/services/open_question_extractor.dart';
import '../../theme/tokens.dart';
import '../submit_confirmation/submit_confirmation_screen.dart';
import 'chrome_bar.dart';
import 'markdown_pane.dart';
import 'typed_review_pane.dart';

/// Review panel — split-pane: real spec markdown on the left, typed
/// review + free-form notes on the right. Questions default to the
/// extractor output of the live `SpecFile` so callers no longer have to
/// hand-plumb them (they previously defaulted to empty, which hid the
/// question cards).
class ReviewPanelScreen extends ConsumerWidget {
  const ReviewPanelScreen({
    required this.jobRef,
    this.questions,
    this.onSubmitTap,
    super.key,
  });

  final JobRef jobRef;

  /// If supplied, overrides the auto-extracted question list (used by
  /// tests and mockup screenshots). Null in production — the screen
  /// extracts questions itself off the loaded spec.
  final List<OpenQuestion>? questions;

  /// Fired when the user taps "Submit review" in the chrome. Default
  /// (null) runs the [ReviewOrchestrator] → [showDialog] flow below.
  final VoidCallback? onSubmitTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final resolvedQuestions = questions ?? _extractQuestions(ref);
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        children: [
          ReviewChromeBar(
            jobRef: jobRef,
            onSubmit: onSubmitTap ?? () => _onSubmit(context, ref),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: MarkdownPane(jobRef: jobRef)),
                SizedBox(
                  width: 420,
                  child: TypedReviewPane(
                    jobRef: jobRef,
                    questions: resolvedQuestions,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<OpenQuestion> _extractQuestions(WidgetRef ref) {
    final spec = ref.watch(specFileProvider(jobRef)).value;
    if (spec == null) return const <OpenQuestion>[];
    return const OpenQuestionExtractor().extract(spec.contents);
  }

  Future<void> _onSubmit(BuildContext context, WidgetRef ref) async {
    final orchestrator = ReviewOrchestrator(ref.read);
    final outcome = await orchestrator.prepare(jobRef);
    if (!context.mounted) return;
    switch (outcome) {
      case ReviewOrchestratorSignInRequired():
        _toast(context, 'Sign in required to submit');
      case ReviewOrchestratorSpecUnavailable():
        _toast(context, 'Spec unavailable - reopen the job');
      case ReviewOrchestratorReady(
          :final source,
          :final questions,
          :final strokeGroups,
          :final identity,
        ):
        final outcome = await showDialog<ReviewSubmission>(
          context: context,
          builder: (_) => SubmitConfirmationScreen(
            jobRef: jobRef,
            source: source,
            questions: questions,
            strokeGroups: strokeGroups,
            identity: identity,
          ),
        );
        if (!context.mounted || outcome == null) return;
        _announceSubmission(context, outcome);
    }
  }

  void _announceSubmission(BuildContext context, ReviewSubmission outcome) {
    final message = switch (outcome) {
      ReviewSubmissionSuccess() =>
        'Review committed locally. Push on next Sync Up.',
      ReviewSubmissionFailure(:final error) => 'Submit failed: $error',
      ReviewSubmissionIdle() || ReviewSubmissionInProgress() => null,
    };
    if (message != null) _toast(context, message);
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
