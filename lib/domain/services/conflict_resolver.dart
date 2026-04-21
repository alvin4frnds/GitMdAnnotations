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
  }) async {
    final backup = await git.backupBranchHead(
      'claude-jobs',
      backupRoot: backupRoot,
    );
    await git.resetHard('origin/claude-jobs');
    await git.mergeInto('origin/main', target: 'claude-jobs');
    return backup;
  }
}
