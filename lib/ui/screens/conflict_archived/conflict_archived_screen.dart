import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/modal_shell.dart';

/// Modal shown after a Sync Up when the remote had diverging commits. Remote
/// wins; the local commits are archived to the on-device backup folder.
class ConflictArchivedScreen extends StatelessWidget {
  const ConflictArchivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ModalShell(
      cardWidth: 580,
      header: ModalHeader(
        icon: Icons.warning_amber_rounded,
        iconBg: t.statusWarning.withValues(alpha: 0.15),
        iconColor: t.statusWarning,
        heading: 'Remote had newer commits',
        descriptionSpans: [
          const TextSpan(
            text: 'Your local changes were archived. ',
          ),
          const TextSpan(
            text: 'Remote takes priority',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const TextSpan(
            text: ' on conflict. Your work is safe at the path below.',
          ),
        ],
      ),
      sections: [
        ModalSunkenSection(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _InfoRow(
                label: 'Backup path',
                value:
                    '~/GitMdScribe/backups/payments-api/claude-jobs-2026-04-20T10-43-01/',
                first: true,
              ),
              _InfoRow(
                label: 'Backed-up commits',
                value: 'f31ac44 review: spec-auth-flow-totp',
              ),
              _InfoRow(
                label: 'Remote now at',
                value: 'a1e9cc2 revise: spec-auth-flow-totp',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: t.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
              children: [
                TextSpan(
                  text: 'Next: ',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(
                  text:
                      're-review against the new remote, or open the backup folder to inspect.',
                ),
              ],
            ),
          ),
        ),
      ],
      footer: const ModalFooter(
        buttons: [
          GhostButton(label: 'Open backup folder'),
          GhostButton(label: 'Discard backup'),
          PrimaryButton(label: 'Continue with remote'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool first;

  const _InfoRow({
    required this.label,
    required this.value,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: first
              ? BorderSide.none
              : BorderSide(color: t.borderSubtle.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: appMono(context, size: 11, color: t.textPrimary),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
