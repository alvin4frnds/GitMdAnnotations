import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/sync_controller.dart';
import '../../../app/providers/sync_providers.dart';
import '../../../domain/ports/git_port.dart';
import '../../../domain/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../_shared/modal_shell.dart';

/// Modal shown after a Sync Up when the remote had diverging commits. Remote
/// wins; the local commits are archived to the on-device backup folder.
///
/// T7 reads the latest [SyncConflictArchived] event out of
/// [SyncController]. If the sync has already settled to [SyncDone] by the
/// time this screen mounts, we fall back to a placeholder caption — M1c
/// P2 follow-up extends `SyncDone` with a nullable `backup` so the banner
/// survives the terminal transition.
class ConflictArchivedScreen extends ConsumerWidget {
  const ConflictArchivedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(syncControllerProvider);
    final backup = _latestBackup(async.value);
    return ModalShell(
      cardWidth: 580,
      header: ModalHeader(
        icon: Icons.warning_amber_rounded,
        iconBg: t.statusWarning.withValues(alpha: 0.15),
        iconColor: t.statusWarning,
        heading: 'Remote had newer commits',
        descriptionSpans: const [
          TextSpan(text: 'Your local changes were archived. '),
          TextSpan(
            text: 'Remote takes priority',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: ' on conflict. Your work is safe at the path below.',
          ),
        ],
      ),
      sections: [
        ModalSunkenSection(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoRow(
                label: 'Backup path',
                value: backup?.path ?? '(not available — sync completed)',
                first: true,
              ),
              _InfoRow(
                label: 'Backed-up commit',
                value: backup?.commitSha ?? '-',
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

  /// Extracts the latest archived [BackupRef] from the sync controller's
  /// state. Both mid-flight [SyncInProgress(SyncConflictArchived(...))]
  /// and the terminal [SyncDone(backup: ...)] carry it, so the banner
  /// survives the final transition (M1c T5 reviewer finding).
  BackupRef? _latestBackup(SyncState? state) {
    if (state is SyncInProgress) {
      final p = state.latest;
      if (p is SyncConflictArchived) return p.backup;
    }
    if (state is SyncDone) return state.backup;
    return null;
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
