import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/modal_shell.dart';

/// Modal shown when the user taps "Submit review" on the review panel.
/// Previews the four files that will be written + the commit message, and
/// warns about offline push deferral.
class SubmitConfirmationScreen extends StatelessWidget {
  const SubmitConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
              _FileListRow(
                prefix: '+',
                name: '03-review.md',
                meta: '1.8 KB',
                first: true,
              ),
              _FileListRow(
                prefix: '+',
                name: '03-annotations.svg',
                meta: '612 B (3 groups)',
              ),
              _FileListRow(
                prefix: '+',
                name: '03-annotations.png',
                meta: '164 KB',
              ),
              _FileListRow(
                prefix: '~',
                name: '02-spec.md',
                meta: 'changelog +1 line',
              ),
            ],
          ),
        ),
        ModalSunkenSection(
          topBorder: false,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModalCaption('Changelog preview'),
              const SizedBox(height: 6),
              Text(
                '- 2026-04-20 09:32 tablet: User clarified auth flow — TOTP required.',
                style: appMono(context, size: 11, color: t.textPrimary),
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
                'review: spec-auth-flow-totp',
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
      footer: const ModalFooter(
        buttons: [
          GhostButton(label: 'Cancel'),
          PrimaryButton(label: 'Submit & commit'),
        ],
      ),
    );
  }
}

class _FileListRow extends StatelessWidget {
  final String prefix;
  final String name;
  final String meta;
  final bool first;

  const _FileListRow({
    required this.prefix,
    required this.name,
    required this.meta,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isAdd = prefix == '+';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: first
              ? BorderSide.none
              : BorderSide(color: t.borderSubtle.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              prefix,
              style: appMono(
                context,
                size: 12,
                weight: FontWeight.w700,
                color: isAdd ? t.statusSuccess : t.statusWarning,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: appMono(context, size: 12, color: t.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            meta,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
