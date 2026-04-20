import 'dart:async';

import '../entities/repo_ref.dart';
import '../ports/git_port.dart';

/// Sealed root of every progress event emitted by [SyncService.syncDown].
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

class SyncComplete extends SyncProgress {
  const SyncComplete();
}

class SyncFailed extends SyncProgress {
  const SyncFailed(this.error);
  final Object error;
}

/// Pure-domain sync orchestrator. Composes [GitPort] to execute Sync Down
/// per IMPLEMENTATION.md §4.6 (FR-1.29, D-13). Sync Up and conflict
/// archival are Milestone 1c — intentionally absent from the public API.
class SyncService {
  const SyncService({required this.git});

  final GitPort git;

  /// Cold stream: each subscription kicks off a fresh run. Emits a terminal
  /// [SyncComplete] or [SyncFailed] and then closes.
  ///
  /// Step order per §4.6 + D-13:
  /// 1. fetch origin/main and origin/claude-jobs (one fetch per branch so
  ///    future adapters can limit bandwidth per branch).
  /// 2. Fast-forward local `main` to `origin/main`. If that merge conflicts
  ///    (which per §4.6 "should never happen" because the tablet never
  ///    commits to main) surface [SyncFailed].
  /// 3. If local `claude-jobs` is missing, skip the merge-into-jobs step.
  ///    Per task brief: real bootstrap (create from origin/main or push)
  ///    lands in M1c; the FakeGitPort can't meaningfully model
  ///    "create-branch-from" without scripting, so we simplify here.
  /// 4. Merge updated local `main` into `claude-jobs`.
  ///
  /// Detecting "local main is actually behind origin" is not possible
  /// through the current [GitPort] surface (no origin-sha reader). The real
  /// adapter's [GitPort.mergeInto] is already defined as fast-forward-only,
  /// so calling it unconditionally is correct: when nothing is ahead, the
  /// merge is a no-op; when origin is ahead, the merge fast-forwards.
  Stream<SyncProgress> syncDown(RepoRef repo, {required String workdir}) {
    final controller = StreamController<SyncProgress>();
    // Fire-and-forget: the controller closes at the end of [_run].
    scheduleMicrotask(() => _run(repo, controller));
    return controller.stream;
  }

  Future<void> _run(
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
}
