import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/modal_shell.dart';

/// Modal shown when the user approves a revised spec for implementation.
/// Creates the empty `05-approved` marker + appends a changelog line.
class ApprovalConfirmationScreen extends StatelessWidget {
  const ApprovalConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ModalShell(
      cardWidth: 540,
      header: ModalHeader(
        icon: Icons.check_rounded,
        iconBg: t.statusSuccess.withValues(alpha: 0.15),
        iconColor: t.statusSuccess,
        heading: 'Approve 04-spec-v2 for implementation?',
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
              _FileListRow(
                prefix: '+',
                name: '05-approved',
                meta: 'empty marker',
                first: true,
              ),
              _FileListRow(
                prefix: '~',
                name: '04-spec-v2.md',
                meta: 'changelog +1 line',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
        ),
      ],
      footer: const ModalFooter(
        buttons: [
          GhostButton(label: 'Keep reviewing'),
          PrimaryButton(label: 'Approve & commit'),
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
