import 'package:flutter/material.dart';

import '_sync_shell.dart';

/// "Sync Down in progress" mockup. Pure visual stub — the spinner animates
/// but there is no real sync work. See `_sync_shell.dart` for the shared
/// layout used by both Sync Down and Sync Up.
class SyncDownScreen extends StatelessWidget {
  const SyncDownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SyncShell(
      direction: SyncDirection.down,
      heading: 'Sync Down in progress',
      subheading: 'Fetching and merging main into claude-jobs',
      logLines: [
        SyncLogLine(
          status: SyncLogStatus.success,
          text: 'fetch origin  —  17.2 MB, 4 refs updated',
        ),
        SyncLogLine(
          status: SyncLogStatus.success,
          text: 'main fast-forwarded to a1e9cc2',
        ),
        SyncLogLine(
          status: SyncLogStatus.active,
          text: 'merging main into claude-jobs…',
        ),
        SyncLogLine(
          status: SyncLogStatus.pending,
          text: 'caching 43 files for offline',
        ),
      ],
      caption:
          'This takes ~4–8 s on typical LTE. Safe to close — resumes next session.',
    );
  }
}
