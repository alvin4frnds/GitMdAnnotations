import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/providers/review_providers.dart';
import '../../../domain/entities/git_identity.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/spec_file.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/file_list_row.dart';
import '../_shared/modal_shell.dart';

/// Modal shown when the user approves a revised spec for implementation.
/// Creates the empty `05-approved` marker + appends a changelog line, via
/// [ReviewController.approve].
class ApprovalConfirmationScreen extends ConsumerWidget {
  const ApprovalConfirmationScreen({
    required this.jobRef,
    required this.source,
    required this.identity,
    this.onCommitted,
    super.key,
  });

  final JobRef jobRef;
  final SpecFile source;
  final GitIdentity identity;
  final ValueChanged<ReviewSubmission>? onCommitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(reviewControllerProvider(jobRef));
    final isInFlight =
        async.value?.submission is ReviewSubmissionInProgress;
    final specName = _basename(source.path);
    return ModalShell(
      cardWidth: 540,
      header: ModalHeader(
        icon: Icons.check_rounded,
        iconBg: t.statusSuccess.withValues(alpha: 0.15),
        iconColor: t.statusSuccess,
        heading: 'Approve $specName for implementation?',
        descriptionSpans: [
          const TextSpan(text: 'Creates '),
          TextSpan(
            text: '05-approved',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const TextSpan(text: ' on '),
          TextSpan(
            text: 'claude-jobs',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const TextSpan(
            text: '. Desktop Claude can now implement and PR to ',
          ),
          TextSpan(
            text: 'main',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const TextSpan(text: '.'),
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
              const FileListRow(
                prefix: '+',
                name: '05-approved',
                meta: 'empty marker',
                first: true,
              ),
              FileListRow(
                prefix: '~',
                name: specName,
                meta: 'changelog +1 line',
              ),
            ],
          ),
        ),
        const _IrreversibleBanner(),
      ],
      footer: ModalFooter(
        buttons: [
          const GhostButton(label: 'Keep reviewing'),
          PrimaryButton(
            label: isInFlight ? 'Committing...' : 'Approve & commit',
            onPressed: isInFlight ? null : () => _approve(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(WidgetRef ref) async {
    final notifier = ref.read(reviewControllerProvider(jobRef).notifier);
    await notifier.approve(source: source, identity: identity);
    final submission = ref.read(reviewControllerProvider(jobRef)).value?.submission;
    if (submission != null) {
      onCommitted?.call(submission);
    }
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

class _IrreversibleBanner extends StatelessWidget {
  const _IrreversibleBanner();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.statusWarning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.statusWarning.withValues(alpha: 0.35)),
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
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: t.statusWarning,
                    fontSize: 12,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(
                      text: 'This is irreversible in-app.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' You can still '),
                    TextSpan(
                      text: 'git revert',
                      style: appMono(
                        context,
                        size: 12,
                        color: t.statusWarning,
                      ),
                    ),
                    const TextSpan(text: ' externally.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
