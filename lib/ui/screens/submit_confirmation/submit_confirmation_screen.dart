import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/providers/review_providers.dart';
import '../../../domain/entities/git_identity.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/spec_file.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../../domain/services/open_question_extractor.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/modal_shell.dart';
import 'planned_writes_preview.dart';

/// Modal shown when the user taps "Submit review" on the review panel.
/// Previews the four files that will be written + the commit message, and
/// warns about offline push deferral.
///
/// T7: preview is driven by [PlannedWritesPreview] which calls
/// [ReviewController] to construct the actual planned writes from the
/// current draft state. The primary button routes through
/// [ReviewController.submit].
class SubmitConfirmationScreen extends ConsumerWidget {
  const SubmitConfirmationScreen({
    required this.jobRef,
    required this.source,
    required this.questions,
    required this.strokeGroups,
    required this.identity,
    this.onCommitted,
    super.key,
  });

  final JobRef jobRef;
  final SpecFile source;
  final List<OpenQuestion> questions;
  final List<StrokeGroup> strokeGroups;
  final GitIdentity identity;

  /// Fired once the Submit commit lands (success or failure — the caller
  /// usually closes the modal and surfaces a toast / error screen).
  final ValueChanged<ReviewSubmission>? onCommitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(reviewControllerProvider(jobRef));
    final isSubmitting =
        async.value?.submission is ReviewSubmissionInProgress;

    return ModalShell(
      cardWidth: 520,
      header: ModalHeader(
        icon: Icons.upload_file_outlined,
        iconBg: t.accentSoftBg,
        iconColor: t.accentPrimary,
        heading: 'Submit review?',
        descriptionSpans: [
          const TextSpan(text: 'Write 03-review.md + annotations and commit to '),
          TextSpan(
            text: 'claude-jobs',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const TextSpan(text: '. No push yet.'),
        ],
      ),
      sections: [
        ModalSunkenSection(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ModalCaption('Files to be committed'),
              const SizedBox(height: 10),
              PlannedWritesPreview(
                jobRef: jobRef,
                source: source,
                strokeGroups: strokeGroups,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModalCaption('commit message'),
              const SizedBox(height: 6),
              Text(
                'review: ${jobRef.jobId}',
                style: appMono(context, size: 11, color: t.textPrimary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.statusWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: t.statusWarning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: t.statusWarning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline — will push on next Sync Up.',
                    style: TextStyle(
                      color: t.statusWarning,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      footer: ModalFooter(
        buttons: [
          const GhostButton(label: 'Cancel'),
          PrimaryButton(
            label: isSubmitting ? 'Committing...' : 'Submit & commit',
            onPressed: isSubmitting ? null : () => _submit(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(WidgetRef ref) async {
    final notifier = ref.read(reviewControllerProvider(jobRef).notifier);
    await notifier.submit(
      source: source,
      questions: questions,
      strokeGroups: strokeGroups,
      identity: identity,
    );
    final submission = ref.read(reviewControllerProvider(jobRef)).value?.submission;
    if (submission != null) {
      onCommitted?.call(submission);
    }
  }
}
