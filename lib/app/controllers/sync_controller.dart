import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/repo_ref.dart';
import '../../domain/ports/git_port.dart';
import '../../domain/services/sync_service.dart';
import '../providers/sync_providers.dart';

/// Sealed UI-level sync state. Exhaustive `switch` in widgets.
sealed class SyncState {
  const SyncState();
}

class SyncIdle extends SyncState {
  const SyncIdle();
}

class SyncInProgress extends SyncState {
  const SyncInProgress(this.latest);
  final SyncProgress latest;
}

class SyncDone extends SyncState {
  const SyncDone(this.at, {this.backup});
  final DateTime at;

  /// If the run encountered a non-fast-forward push that archived local
  /// commits before resetting, this is the backup handle — non-null only
  /// on the archive-and-reset path. Surface in the UI so the "Remote
  /// won, backup at `<path>`" banner survives the terminal transition
  /// out of [SyncInProgress] (M1c T5 reviewer finding).
  final BackupRef? backup;
}

class SyncErrored extends SyncState {
  const SyncErrored(this.error);
  final Object error;
}

/// Drives the UI through a sync run. Subscribes to
/// [SyncService.syncDown] / [SyncService.syncUp] and maps each
/// [SyncProgress] event into a [SyncState]. Terminal progress events flip
/// state to [SyncDone] / [SyncErrored].
///
/// Follow-up: we use [DateTime.now] directly for the `SyncDone.at`
/// timestamp. If we add sync telemetry in M1d we'll wire a `Clock` port
/// here for determinism.
class SyncController extends AsyncNotifier<SyncState> {
  bool _running = false;

  SyncService get _service => ref.read(syncServiceProvider);

  @override
  Future<SyncState> build() async => const SyncIdle();

  Future<void> syncDown({
    required RepoRef repo,
    required String workdir,
  }) async {
    if (_running) return;
    _running = true;
    try {
      await for (final p in _service.syncDown(repo, workdir: workdir)) {
        if (p is SyncComplete) {
          state = AsyncValue.data(SyncDone(DateTime.now()));
        } else if (p is SyncFailed) {
          state = AsyncValue.data(SyncErrored(p.error));
        } else {
          state = AsyncValue.data(SyncInProgress(p));
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Push local `claude-jobs` to origin (§4.6 FR-1.30). Mirrors
  /// [syncDown]: subscribes to the service stream, maps each progress
  /// event onto [SyncState], and guards re-entry with [_running].
  ///
  /// A [SyncConflictArchived] event flows through [SyncInProgress] — the
  /// UI inspects `state.latest` to render the "remote won, backup at …"
  /// banner before the stream reaches its terminal [SyncDone]. We also
  /// capture the [BackupRef] into the terminal [SyncDone.backup] so the
  /// banner survives the final transition (M1c T5 reviewer finding).
  Future<void> syncUp({
    required RepoRef repo,
    required String workdir,
    required String backupRoot,
  }) async {
    if (_running) return;
    _running = true;
    BackupRef? archivedBackup;
    try {
      await for (final p in _service.syncUp(
        repo,
        workdir: workdir,
        backupRoot: backupRoot,
      )) {
        if (p is SyncConflictArchived) {
          archivedBackup = p.backup;
          state = AsyncValue.data(SyncInProgress(p));
        } else if (p is SyncComplete) {
          state = AsyncValue.data(
            SyncDone(DateTime.now(), backup: archivedBackup),
          );
        } else if (p is SyncFailed) {
          state = AsyncValue.data(SyncErrored(p.error));
        } else {
          state = AsyncValue.data(SyncInProgress(p));
        }
      }
    } finally {
      _running = false;
    }
  }
}
