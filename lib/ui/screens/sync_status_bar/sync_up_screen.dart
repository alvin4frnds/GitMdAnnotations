import 'package:flutter/material.dart';

import '_sync_shell.dart';

/// "Sync Up in progress" mockup. Pure visual stub — the spinner animates
/// but there is no real sync work. See `_sync_shell.dart` for the shared
/// layout used by both Sync Down and Sync Up.
class SyncUpScreen extends StatelessWidget {
  const SyncUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SyncShell(
      direction: SyncDirection.up,
      heading: 'Sync Up in progress',
      subheading: 'Pushing claude-jobs to origin',
      logLines: [
        SyncLogLine(
          status: SyncLogStatus.success,
          text: '4 files staged',
        ),
        SyncLogLine(
          status: SyncLogStatus.success,
          text: 'commit f31ac44  —  review: spec-auth-flow-totp',
        ),
        SyncLogLine(
          status: SyncLogStatus.active,
          text: 'pushing to origin/claude-jobs  (43%)',
        ),
        SyncLogLine(
          status: SyncLogStatus.pending,
          text: 'verifying remote',
        ),
      ],
      caption:
          'This takes ~4–8 s on typical LTE. Safe to close — resumes next session.',
    );
  }
}
