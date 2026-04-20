import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/git_port.dart';
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

/// Pure-domain sync orchestrator. Recomputed when [gitPortProvider] is
/// replaced (e.g. when we swap fakes in tests).
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(git: ref.watch(gitPortProvider)),
);

/// UI-facing sync state machine. See [SyncController].
final syncControllerProvider =
    AsyncNotifierProvider<SyncController, SyncState>(SyncController.new);
