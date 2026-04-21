import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/job_list_controller.dart';
import '../../../app/controllers/sync_controller.dart';
import '../../../app/last_session.dart';
import '../../../app/providers/auth_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../app/providers/sync_providers.dart';
import '../../../domain/entities/job.dart';
import '../../../domain/entities/phase.dart';
import '../../../domain/entities/repo_ref.dart';
import '../../../domain/entities/source_kind.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../changelog_viewer/changelog_viewer_screen.dart';
import '../settings/settings_screen.dart';
import '../spec_reader_md/spec_reader_md_screen.dart';
import '../spec_reader_pdf/spec_reader_pdf_screen.dart';

/// Screen 3 — Job list / pending specs. T12 replaces the inline stub data
/// with [jobListControllerProvider]; phase/sourceKind colour mapping lives
/// in [_PhaseTag] / [_FileKindChip] below.
///
/// Follow-up: the `just arrived` treatment (indigo left-rail accent + "just
/// arrived" caption) is dropped in M1a because `Job` doesn't expose an
/// arrival timestamp yet. Restore once sync telemetry ships.
class JobListScreen extends ConsumerWidget {
  const JobListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(jobListControllerProvider);
    final repo = ref.watch(currentRepoProvider);
    return ColoredBox(
      color: t.surfaceBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LeftRail(async: async),
          Expanded(
            child: _MainArea(async: async, repo: repo),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left rail
// ---------------------------------------------------------------------------

class _LeftRail extends ConsumerWidget {
  const _LeftRail({required this.async});
  final AsyncValue<JobListState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final counts = _phaseCounts(async);
    final repo = ref.watch(currentRepoProvider);
    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(right: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RepoSwitcherButton(
            repo: repo,
            onPressed: () => _confirmChangeRepo(context, ref),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          const _SectionHeader(label: 'Phase'),
          const SizedBox(height: 8),
          _FilterRow(label: 'All', count: '${counts.all}', selected: true),
          const SizedBox(height: 2),
          _FilterRow(label: 'Awaiting review', count: '${counts.review}'),
          const SizedBox(height: 2),
          _FilterRow(label: 'Awaiting revision', count: '${counts.revised}'),
          const SizedBox(height: 2),
          _FilterRow(label: 'Approved', count: '${counts.approved}'),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          _NewSpecButton(onPressed: () {}),
          const SizedBox(height: 8),
          _ChangelogNavButton(
            onPressed: () => _openChangelog(context),
          ),
          const SizedBox(height: 8),
          _SettingsNavButton(
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
    );
  }

  /// Same confirm-dialog + clear-state flow Settings uses. Duplicated
  /// rather than extracted because it's ten lines of UI glue — if a
  /// third call site shows up, lift it into a shared helper.
  Future<void> _confirmChangeRepo(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Change repository?'),
        content: const Text(
          'You stay signed in. Pending local commits remain on disk under '
          "the current repo's workdir — switch back to see them again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Change repo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await clearLastSession(ref.read(secureStorageProvider));
    ref.read(currentRepoProvider.notifier).state = null;
    ref.read(currentWorkdirProvider.notifier).state = null;
  }

  /// Pushes the cross-job changelog timeline. Entry point wired from the
  /// left rail per M1d-T1; JobList remains the top-of-stack, so
  /// Navigator.pop() returns here.
  void _openChangelog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: ChangelogViewerScreen()),
      ),
    );
  }

  /// Pushes the Settings screen (M1d-T2). Sibling to [_openChangelog];
  /// the Settings screen owns its own scaffold + back button.
  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  _PhaseCounts _phaseCounts(AsyncValue<JobListState> async) {
    final state = async.value;
    if (state is! JobListLoaded) return const _PhaseCounts.zero();
    var review = 0;
    var revised = 0;
    var approved = 0;
    for (final j in state.jobs) {
      switch (j.phase) {
        case Phase.review:
          review++;
        case Phase.revised:
          revised++;
        case Phase.approved:
          approved++;
        case Phase.spec:
          // Pre-review phase — not surfaced as a bucket in the rail.
          break;
      }
    }
    return _PhaseCounts(
      all: state.jobs.length,
      review: review,
      revised: revised,
      approved: approved,
    );
  }
}

class _PhaseCounts {
  const _PhaseCounts({
    required this.all,
    required this.review,
    required this.revised,
    required this.approved,
  });
  const _PhaseCounts.zero()
      : all = 0,
        review = 0,
        revised = 0,
        approved = 0;
  final int all;
  final int review;
  final int revised;
  final int approved;
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: t.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final String count;
  final bool selected;
  const _FilterRow({required this.label, required this.count, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = selected ? t.accentSoftBg : Colors.transparent;
    final fg = selected ? t.accentPrimary : t.textPrimary;
    final countFg = selected ? t.accentPrimary : t.textMuted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {},
        hoverColor: selected ? t.accentSoftBg : t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                count,
                style: TextStyle(color: countFg, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewSpecButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _NewSpecButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accentPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_rounded, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'New spec',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-of-sidebar repo switcher. Shows the active repo as
/// `owner/name` in mono plus a small ⇄ affordance so the user can
/// flip to another repo without digging into Settings. Tapping runs
/// the same confirm-dialog + clear-state flow as Settings → Change.
/// Renders a muted placeholder when no repo is active (in practice
/// _AuthGate would have routed to RepoPicker in that case — this is
/// belt-and-braces for widget-test surfaces).
class _RepoSwitcherButton extends StatelessWidget {
  const _RepoSwitcherButton({required this.repo, required this.onPressed});

  final RepoRef? repo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = repo == null ? 'No repository' : '${repo!.owner}/${repo!.name}';
    return InkWell(
      onTap: repo == null ? null : onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open_rounded, size: 14, color: t.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: appMono(
                  context,
                  size: 12,
                  weight: FontWeight.w600,
                  color: repo == null ? t.textMuted : t.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: repo == null ? t.textMuted : t.accentPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary nav button that pushes the cross-job ChangelogViewer
/// (M1d-T1). Ghost/outlined style so it doesn't compete with the primary
/// "New spec" CTA — same visual treatment as the top-chrome ghost
/// buttons.
class _ChangelogNavButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ChangelogNavButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: t.borderSubtle),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 16, color: t.textPrimary),
            const SizedBox(width: 6),
            const Text('Changelog'),
          ],
        ),
      ),
    );
  }
}

/// Secondary nav button that pushes the Settings screen (M1d-T2).
/// Same ghost/outlined treatment as [_ChangelogNavButton].
class _SettingsNavButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SettingsNavButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: t.borderSubtle),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_rounded, size: 16, color: t.textPrimary),
            const SizedBox(width: 6),
            const Text('Settings'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main area
// ---------------------------------------------------------------------------

class _MainArea extends StatelessWidget {
  const _MainArea({required this.async, required this.repo});
  final AsyncValue<JobListState> async;
  final RepoRef? repo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopChrome(async: async, repo: repo),
        Expanded(child: _JobListBody(async: async)),
      ],
    );
  }
}

class _TopChrome extends ConsumerWidget {
  const _TopChrome({required this.async, required this.repo});
  final AsyncValue<JobListState> async;
  final RepoRef? repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = async.value;
    final hasRepo = state is JobListLoaded;
    final jobCount = state is JobListLoaded ? state.jobs.length : 0;
    // Watch sync state so the buttons disable mid-flight and the
    // snackbar + list refresh fire exactly once at terminal states.
    ref.listen<AsyncValue<SyncState>>(syncControllerProvider, (prev, next) {
      final prevVal = prev?.value;
      final nextVal = next.value;
      if (prevVal == nextVal) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (nextVal is SyncDone) {
        final note = nextVal.backup == null
            ? 'Sync complete'
            : 'Sync complete — remote won, backup at '
                '${nextVal.backup!.path}';
        messenger?.showSnackBar(SnackBar(
          content: Text(note),
          duration: const Duration(seconds: 4),
        ));
        // Terminal success — rediscover jobs on disk so JobList picks
        // up anything that was fetched. Re-query the unpushed-count
        // badge too; Sync Up success empties the queue to 0, Sync Down
        // merges remote in and leaves local tip unchanged so the
        // number only changes when local was already ahead.
        ref.invalidate(jobListControllerProvider);
        ref.invalidate(pendingPushCountProvider);
      } else if (nextVal is SyncErrored) {
        messenger?.showSnackBar(SnackBar(
          content: Text('Sync failed: ${nextVal.error}'),
          backgroundColor: t.statusDanger,
          duration: const Duration(seconds: 6),
        ));
      }
    });
    final syncState = ref.watch(syncControllerProvider).value;
    final syncInFlight = syncState is SyncInProgress;
    final workdir = ref.watch(currentWorkdirProvider);
    final canSync = hasRepo && repo != null && workdir != null && !syncInFlight;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            repo?.name ?? '—',
            style: appMono(context, size: 12, weight: FontWeight.w600),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '·',
              style: appMono(context, size: 12, color: t.textMuted),
            ),
          ),
          Text(
            'claude-jobs',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const SizedBox(width: 16),
          Text(
            '$jobCount jobs',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const Spacer(),
          _GhostButton(
            icon: Icons.arrow_downward_rounded,
            label: syncState is SyncInProgress ? 'Syncing…' : 'Sync Down',
            onPressed: canSync
                ? () => ref
                    .read(syncControllerProvider.notifier)
                    .syncDown(repo: repo!, workdir: workdir)
                : null,
          ),
          const SizedBox(width: 8),
          _SyncUpButton(
            onPressed: canSync
                ? () => ref
                    .read(syncControllerProvider.notifier)
                    .syncUp(
                      repo: repo!,
                      workdir: workdir,
                      backupRoot: '$workdir/.gitmdscribe-backups',
                    )
                : null,
            badgeCount: hasRepo
                ? (ref.watch(pendingPushCountProvider).value ?? 0).toString()
                : '—',
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _GhostButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: t.borderSubtle),
        ),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SyncUpButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String badgeCount;
  const _SyncUpButton({required this.onPressed, required this.badgeCount});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          const Text(
            'Sync Up',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: t.statusWarning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeCount,
              style: TextStyle(
                color: t.statusWarning,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — switches on the AsyncValue<JobListState>
// ---------------------------------------------------------------------------

class _JobListBody extends StatelessWidget {
  const _JobListBody({required this.async});
  final AsyncValue<JobListState> async;

  @override
  Widget build(BuildContext context) {
    if (async.isLoading && !async.hasValue) {
      return const _LoadingState();
    }
    if (async.hasError && !async.hasValue) {
      return _ErrorState(message: async.error.toString());
    }
    final state = async.value;
    if (state is JobListEmpty) return const _EmptyState();
    if (state is JobListLoaded) {
      if (state.jobs.isEmpty) return const _EmptyState(reason: 'No jobs');
      return _JobRows(jobs: state.jobs);
    }
    // Fallback (should not happen — AsyncNotifier always lands in a sealed
    // JobListState). Show a spinner rather than an empty frame.
    return const _LoadingState();
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: t.statusDanger.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.statusDanger.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: t.statusDanger),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: t.statusDanger,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.reason = 'No repo selected'});
  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 32, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            reason,
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _JobRows extends StatelessWidget {
  const _JobRows({required this.jobs});
  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    for (var i = 0; i < jobs.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: t.borderSubtle));
      }
      rows.add(_JobRow(job: jobs[i]));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  final Job job;
  const _JobRow({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Material(
      color: t.surfaceBackground,
      child: InkWell(
        onTap: () => _openJob(context, ref),
        hoverColor: t.surfaceSunken,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.transparent, width: 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _PhaseTag(phase: job.phase),
                        const SizedBox(width: 8),
                        _FileKindChip(kind: job.sourceKind),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            job.ref.jobId,
                            style: appMono(
                              context,
                              size: 13,
                              weight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Push the appropriate SpecReader for this job.
  ///
  /// - [SourceKind.markdown] → [SpecReaderMdScreen] (current body is
  ///   still the UI spike's hardcoded content; the real spec-loading
  ///   pipeline will arrive with the md-renderer wiring in M1d).
  /// - [SourceKind.pdf] → [SpecReaderPdfScreen] with the resolved
  ///   `<workdir>/jobs/pending/<jobId>/spec.pdf`.
  ///
  /// Falls back silently if the workdir isn't set — in practice that
  /// only happens before a repo is picked, in which case no rows render.
  void _openJob(BuildContext context, WidgetRef ref) {
    final workdir = ref.read(currentWorkdirProvider);
    if (workdir == null) return;
    // Persist the jobId so the next cold start can restore where the
    // user left off (NFR-2). Fire-and-forget — a failure here mustn't
    // block navigation.
    saveLastOpenedJobId(ref.read(secureStorageProvider), job.ref.jobId);
    final screen = switch (job.sourceKind) {
      SourceKind.markdown => SpecReaderMdScreen(jobRef: job.ref),
      SourceKind.pdf => SpecReaderPdfScreen(
          jobRef: job.ref,
          filePath: '$workdir/jobs/pending/${job.ref.jobId}/spec.pdf',
        ),
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: screen),
      ),
    );
  }
}

class _PhaseTag extends StatelessWidget {
  final Phase phase;
  const _PhaseTag({required this.phase});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Phase colour mapping — ties back to §4.3's phase truth table.
    //   review   → indigo   (awaiting review)
    //   revised  → amber    (awaiting revision)
    //   approved → green    (approved, read-only)
    //   spec     → muted    (pre-review; rarely shown here but covered)
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (phase) {
      case Phase.review:
        bg = t.accentSoftBg;
        fg = t.accentPrimary;
        label = 'Awaiting review';
      case Phase.revised:
        bg = t.statusWarning.withValues(alpha: 0.15);
        fg = t.statusWarning;
        label = 'Awaiting revision';
      case Phase.approved:
        bg = t.statusSuccess.withValues(alpha: 0.15);
        fg = t.statusSuccess;
        label = 'Approved';
      case Phase.spec:
        bg = t.surfaceSunken;
        fg = t.textMuted;
        label = 'Spec';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FileKindChip extends StatelessWidget {
  final SourceKind kind;
  const _FileKindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = kind == SourceKind.markdown ? '.md' : '.pdf';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Text(
        label,
        style: appMono(context, size: 10, color: t.textMuted),
      ),
    );
  }
}
