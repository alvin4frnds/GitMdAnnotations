import '../entities/repo_ref.dart';
import '../ports/git_port.dart';

/// Pure-domain orchestrator of the "remote wins" archival flow described
/// by PRD §5.7 FR-1.32 and IMPLEMENTATION.md §4.6.
///
/// When a Sync Up push is rejected (non-fast-forward) we cannot merge the
/// divergent `claude-jobs` history on-device — per D-4 / D-7 the remote is
/// always authoritative. Instead we archive the local HEAD to on-device
/// storage (so nothing is lost), hard-reset `claude-jobs` to
/// `origin/claude-jobs`, and re-apply `origin/main` on top (D-13, so newly
/// arrived source in `main` still propagates into the sidecar).
///
/// Wiring: `SyncService.syncUp` (T5) calls [archiveAndReset] when
/// `GitPort.push` returns [PushRejectedNonFastForward], then surfaces the
/// returned [BackupRef] to the UI as "Local changes archived — remote took
/// precedence. Backup at `<path>`."
class ConflictResolver {
  const ConflictResolver({required this.git});

  final GitPort git;

  /// Archive the current HEAD of `claude-jobs` to [backupRoot], reset
  /// local `claude-jobs` to `origin/claude-jobs`, and merge `origin/main`
  /// on top. Returns the [BackupRef] referencing the archived pre-reset
  /// state.
  ///
  /// Preconditions: the adapter's workdir has already been initialized
  /// (i.e. `cloneOrOpen` ran earlier in the session). No workdir parameter
  /// is accepted here — workdir state lives inside the port.
  ///
  /// Throws [GitMergeConflict] if merging `origin/main` into the reset
  /// `claude-jobs` still conflicts. In practice this requires a force-push
  /// on `main` (extremely rare); the exception bubbles so the UI can
  /// surface it. The backup is *not* rolled back — the archived copy is
  /// preserved so the user can recover by hand.
  Future<BackupRef> archiveAndReset(
    RepoRef repo, {
    required String backupRoot,
    bool tolerateMergeConflict = false,
  }) async {
    final backup = await git.backupBranchHead(
      'claude-jobs',
      backupRoot: backupRoot,
    );
    // Refresh the local remote-tracking refs before reset. Push observed
    // the remote state over the wire to detect non-fast-forward, but it
    // does not update `refs/remotes/origin/<branch>` — so
    // `resetHard('origin/claude-jobs')` without this fetch would reset to
    // the stale pre-push snapshot and silently drop remote commits added
    // by other devices. integration_test/sync_conflict_test.dart surfaces
    // this — the remote-added file is only visible after the fetch.
    await git.fetch(repo, branch: 'claude-jobs');
    await git.fetch(repo, branch: repo.defaultBranch);
    await git.resetHard('origin/claude-jobs');
    // Re-apply origin/<defaultBranch> on top of origin/claude-jobs so
    // newly-arrived source on main propagates into the sidecar
    // (D-13). When [tolerateMergeConflict] is set and the merge
    // conflicts (origin/main and origin/claude-jobs disagree on
    // shared files), accept origin/claude-jobs as-is — local state is
    // already coherent thanks to the resetHard above and the archived
    // backup still preserves any pre-reset work. The default behavior
    // preserves the Sync Up contract: propagate the conflict so the
    // caller can surface a typed failure.
    try {
      await git.mergeInto(
        'origin/${repo.defaultBranch}',
        target: 'claude-jobs',
      );
      // Seal a successful non-fast-forward merge so the merged state
      // persists past the next sync's [abortMergeStateIfAny] preamble
      // — without this, the merge is silently dropped and the next
      // sync would re-trigger archiveAndReset.
      await git.sealInProgressMerge(
        branch: 'claude-jobs',
        message:
            'sync: merge origin/${repo.defaultBranch} into claude-jobs '
            '(remote-wins archive-and-reset)',
      );
    } on GitMergeConflict {
      if (!tolerateMergeConflict) rethrow;
    }
    return backup;
  }
}
