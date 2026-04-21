import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/git_port.dart';
import '../../domain/services/conflict_resolver.dart';
import '../../domain/services/sync_service.dart';
import '../controllers/sync_controller.dart';

/// Binds the [GitPort] implementation at composition root. Tests override
/// with a `FakeGitPort`; the production binding is attached in `main.dart`
/// once the libgit2-backed `GitAdapter` ships in T10.
final gitPortProvider = Provider<GitPort>((ref) {
  throw UnimplementedError(
    'gitPortProvider must be overridden at composition root',
  );
});

/// Remote-wins archive-and-reset orchestrator used by Sync Up when a push
/// is rejected non-fast-forward. Recomputed when [gitPortProvider] is
/// replaced so fakes propagate automatically.
final conflictResolverProvider = Provider<ConflictResolver>(
  (ref) => ConflictResolver(git: ref.watch(gitPortProvider)),
);

/// Pure-domain sync orchestrator. Recomputed when [gitPortProvider] or
/// [conflictResolverProvider] is replaced (e.g. when we swap fakes in
/// tests).
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    git: ref.watch(gitPortProvider),
    conflictResolver: ref.watch(conflictResolverProvider),
  ),
);

/// UI-facing sync state machine. See [SyncController].
final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncState>(SyncController.new);

/// Count of local commits on `claude-jobs` that are ahead of
/// `origin/claude-jobs`. Drives the JobList chrome's "Sync Up [N]"
/// badge so users can see at a glance how many local submits are
/// queued up waiting for a push.
///
/// Returns 0 when the port throws (e.g. no repo open yet during an
/// early cold start, a fresh clone before the first fetch). Callers
/// in the commit path (`ReviewController.submit` / `.approve`) and
/// the sync path (`SyncController.syncUp`) `ref.invalidate` this
/// provider on success so the badge re-queries — the value is cheap
/// (one libgit2 `graph_ahead_behind` call) so a naive recompute is
/// fine.
final pendingPushCountProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(gitPortProvider).countCommitsAhead(
          localBranch: 'claude-jobs',
          remoteBranch: 'origin/claude-jobs',
        );
  } catch (_) {
    return 0;
  }
});
