import 'dart:async';

import '../entities/repo_ref.dart';
import '../ports/git_port.dart';
import 'conflict_resolver.dart';

/// Sealed root of every progress event emitted by [SyncService.syncDown]
/// and [SyncService.syncUp].
///
/// The UI `switch`es exhaustively on concrete subtypes. Terminal states are
/// [SyncComplete] (success) and [SyncFailed] (typed error); after either,
/// the stream closes and no further events arrive.
sealed class SyncProgress {
  const SyncProgress();
}

class SyncStarted extends SyncProgress {
  const SyncStarted();
}

class SyncFetching extends SyncProgress {
  const SyncFetching();
}

class SyncFastForwardingMain extends SyncProgress {
  const SyncFastForwardingMain();
}

class SyncMergingMainIntoJobs extends SyncProgress {
  const SyncMergingMainIntoJobs();
}

/// Emitted by [SyncService.syncDown] on a repo where origin has no
/// `claude-jobs` branch yet. The service seeds a local `claude-jobs` from
/// `origin/<default>` and pushes it to origin so the repo becomes usable
/// on its first pull instead of silently terminating with an empty list.
class SyncInitializingSidecar extends SyncProgress {
  const SyncInitializingSidecar();
}

class SyncPushing extends SyncProgress {
  const SyncPushing();
}

/// Emitted by [SyncService.syncUp] when a non-fast-forward push was
/// rejected and [ConflictResolver.archiveAndReset] succeeded. [backup]
/// points at the on-device archive of the pre-reset `claude-jobs` HEAD
/// so the UI can surface "Local changes archived — backup at `<path>`".
class SyncConflictArchived extends SyncProgress {
  const SyncConflictArchived(this.backup);
  final BackupRef backup;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncConflictArchived && other.backup == backup;

  @override
  int get hashCode => backup.hashCode;

  @override
  String toString() => 'SyncConflictArchived($backup)';
}

class SyncComplete extends SyncProgress {
  const SyncComplete();
}

class SyncFailed extends SyncProgress {
  const SyncFailed(this.error);
  final Object error;
}

/// Pure-domain sync orchestrator. Composes [GitPort] (and a
/// [ConflictResolver] for Sync Up's archive-and-reset path) to execute
/// both directions of the sync flow per IMPLEMENTATION.md §4.6
/// (FR-1.29–FR-1.33, D-13).
class SyncService {
  SyncService({required this.git, ConflictResolver? conflictResolver})
      : _conflictResolver =
            conflictResolver ?? ConflictResolver(git: git);

  final GitPort git;
  final ConflictResolver _conflictResolver;

  /// Cold stream: each subscription kicks off a fresh run. Emits a terminal
  /// [SyncComplete] or [SyncFailed] and then closes.
  ///
  /// Step order per §4.6 + D-13:
  /// 1. fetch origin/main and origin/claude-jobs (per-branch so future
  ///    adapters can limit bandwidth).
  /// 2. Fast-forward `main` to `origin/main`. Conflict here "should
  ///    never happen" (tablet never commits to main) but surfaces
  ///    [SyncFailed] if it does.
  /// 3. If local `claude-jobs` is missing, skip the merge-into-jobs step
  ///    (real bootstrap lands in M1c).
  /// 4. Merge `main` into `claude-jobs`.
  ///
  /// [GitPort.mergeInto] is fast-forward-only so calling it
  /// unconditionally is correct — a no-op when nothing is ahead.
  Stream<SyncProgress> syncDown(RepoRef repo, {required String workdir}) {
    final controller = StreamController<SyncProgress>();
    // Fire-and-forget: the controller closes at the end of [_runDown].
    scheduleMicrotask(() => _runDown(repo, controller));
    return controller.stream;
  }

  /// Cold stream: pushes local `claude-jobs` to origin per §4.6 / FR-1.30.
  /// Happy path emits `Started -> Pushing -> Complete`.
  ///
  /// Non-fast-forward rejection invokes [ConflictResolver.archiveAndReset]
  /// (remote-wins per D-4/D-7): archive pre-reset HEAD to [backupRoot],
  /// hard-reset to `origin/claude-jobs`, merge `origin/main` back in. We
  /// do **not** re-push — post-archive the local tree equals the remote.
  /// Event sequence: `Started -> Pushing -> ConflictArchived -> Complete`.
  ///
  /// Auth rejection surfaces `SyncFailed(PushRejectedAuth())` so the UI
  /// can route to re-auth.
  Stream<SyncProgress> syncUp(
    RepoRef repo, {
    required String workdir,
    required String backupRoot,
  }) {
    final controller = StreamController<SyncProgress>();
    scheduleMicrotask(() => _runUp(repo, backupRoot, controller));
    return controller.stream;
  }

  Future<void> _runDown(
    RepoRef repo,
    StreamController<SyncProgress> out,
  ) async {
    try {
      out.add(const SyncStarted());

      final defaultBranch = repo.defaultBranch;
      out.add(const SyncFetching());
      await git.fetch(repo, branch: defaultBranch);
      await git.fetch(repo, branch: 'claude-jobs');

      out.add(const SyncFastForwardingMain());
      try {
        await git.mergeInto(
          'origin/$defaultBranch',
          target: defaultBranch,
        );
      } on GitMergeConflict catch (e) {
        out.add(SyncFailed(e));
        return;
      }

      // If local claude-jobs doesn't exist yet but the origin has one
      // (common case: the repo was cloned before the sidecar branch was
      // pushed, then Sync Down should pull it), create the local branch
      // pointing at origin/claude-jobs so the merge step below has
      // something to merge into and checking it out populates the
      // working tree with jobs/pending/*. Without this the sync
      // silently "succeeds" but JobList stays empty because HEAD is
      // still on the default branch.
      final jobsHead = await git.headSha('claude-jobs');
      if (jobsHead == null) {
        var bootstrapped = await git.bootstrapLocalBranchFromRemote(
          localBranch: 'claude-jobs',
          remoteBranch: 'origin/claude-jobs',
        );
        if (!bootstrapped) {
          // Origin has no claude-jobs yet — seed one from the default
          // branch so a freshly-picked repo becomes usable on its first
          // pull. Without this, every repo except pre-bootstrapped ones
          // (like the test `surri` fixture) terminates with a silent
          // "Sync complete" and an empty JobList.
          out.add(const SyncInitializingSidecar());
          bootstrapped = await git.bootstrapLocalBranchFromRemote(
            localBranch: 'claude-jobs',
            remoteBranch: 'origin/$defaultBranch',
          );
          if (!bootstrapped) {
            // Origin has no default branch either — the repo is empty.
            // Surface the real reason instead of a silent no-op.
            out.add(SyncFailed(
              StateError(
                'Repo has no commits on origin/$defaultBranch — '
                'push an initial commit before syncing.',
              ),
            ));
            return;
          }
          final pushOutcome = await git.push(repo, branch: 'claude-jobs');
          switch (pushOutcome) {
            case PushSuccess():
              break;
            case PushRejectedAuth():
              out.add(const SyncFailed(PushRejectedAuth()));
              return;
            case PushRejectedNonFastForward():
              // Another device seeded origin/claude-jobs between our
              // fetch and our push — rare race. Surface the outcome so
              // the user can re-tap; the next pull hits the
              // bootstrap-from-origin/claude-jobs path normally.
              out.add(SyncFailed(pushOutcome));
              return;
          }
        }
      }

      out.add(const SyncMergingMainIntoJobs());
      try {
        await git.mergeInto(defaultBranch, target: 'claude-jobs');
      } on GitMergeConflict catch (e) {
        out.add(SyncFailed(e));
        return;
      }

      out.add(const SyncComplete());
    } catch (e) {
      out.add(SyncFailed(e));
    } finally {
      await out.close();
    }
  }

  Future<void> _runUp(
    RepoRef repo,
    String backupRoot,
    StreamController<SyncProgress> out,
  ) async {
    try {
      out.add(const SyncStarted());
      out.add(const SyncPushing());
      final outcome = await git.push(repo, branch: 'claude-jobs');
      switch (outcome) {
        case PushSuccess():
          out.add(const SyncComplete());
        case PushRejectedNonFastForward():
          try {
            final backup = await _conflictResolver.archiveAndReset(
              repo,
              backupRoot: backupRoot,
            );
            out.add(SyncConflictArchived(backup));
            out.add(const SyncComplete());
          } on GitMergeConflict catch (e) {
            out.add(SyncFailed(e));
          }
        case PushRejectedAuth():
          out.add(const SyncFailed(PushRejectedAuth()));
      }
    } catch (e) {
      out.add(SyncFailed(e));
    } finally {
      await out.close();
    }
  }
}
