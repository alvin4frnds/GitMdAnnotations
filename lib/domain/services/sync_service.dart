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

      out.add(const SyncFetching());
      await git.fetch(repo, branch: 'main');
      await git.fetch(repo, branch: 'claude-jobs');

      out.add(const SyncFastForwardingMain());
      try {
        await git.mergeInto('origin/main', target: 'main');
      } on GitMergeConflict catch (e) {
        out.add(SyncFailed(e));
        return;
      }

      // Bootstrap simplification: if local claude-jobs doesn't exist we
      // can't meaningfully merge into it here. M1c will handle real
      // "create-from-origin-or-main + push" bootstrap. For M1a we just
      // complete the sync — Sync Down is still idempotent.
      final jobsHead = await git.headSha('claude-jobs');
      if (jobsHead == null) {
        out.add(const SyncComplete());
        return;
      }

      out.add(const SyncMergingMainIntoJobs());
      try {
        await git.mergeInto('main', target: 'claude-jobs');
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
