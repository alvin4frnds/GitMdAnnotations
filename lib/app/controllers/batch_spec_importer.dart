import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/repo_ref.dart';
import '../providers/annotation_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';
import 'auth_controller.dart';
import 'spec_importer.dart';

/// Sealed UI-level state for a batch "Convert to spec" run. Exhaustive
/// `switch` in widgets. Mirrors [SyncState]'s shape (spec-005 §8b): a
/// `_running` guard + a synchronous flip to [BatchRunning] on start.
sealed class BatchConvertState {
  const BatchConvertState();
}

class BatchIdle extends BatchConvertState {
  const BatchIdle();
}

class BatchRunning extends BatchConvertState {
  const BatchRunning({
    required this.total,
    required this.done,
    required this.currentRelPath,
    required this.failures,
  });

  /// Total files in the batch.
  final int total;

  /// 1-based index of the file currently being converted, so the bar
  /// advances 1/total … total/total as work proceeds.
  final int done;
  final String currentRelPath;
  final List<BatchFailure> failures;
}

class BatchFinished extends BatchConvertState {
  const BatchFinished({
    required this.converted,
    required this.failures,
    required this.cancelled,
  });
  final List<JobRef> converted;
  final List<BatchFailure> failures;
  final bool cancelled;
}

/// A single file that could not be converted, with a user-facing reason.
class BatchFailure {
  const BatchFailure({required this.relPath, required this.message});
  final String relPath;
  final String message;
}

/// Loops the existing single-file [SpecImporter] once per selected file —
/// one commit per file on `claude-jobs` (spec-005). Skips failures and
/// reports them; supports "finish current, then stop" cancellation and
/// in-batch jobId reservation so same-slug files don't clobber each other.
class BatchConvertController extends AutoDisposeNotifier<BatchConvertState> {
  bool _running = false;
  bool _cancelRequested = false;

  @override
  BatchConvertState build() => const BatchIdle();

  /// Requests a stop. Honoured **between** files only — a git commit is not
  /// safely interruptible mid-write (spec-005 OQ-3).
  void cancel() => _cancelRequested = true;

  Future<void> run(List<String> relPaths) async {
    if (_running || relPaths.isEmpty) return;
    final repo = ref.read(currentRepoProvider);
    final workdir = ref.read(currentWorkdirProvider);
    if (repo == null || workdir == null) {
      state = _allFailed(relPaths, 'Open a repository first.');
      return;
    }
    _running = true;
    _cancelRequested = false;
    // Flip in-flight synchronously so the determinate bar shows from the
    // first frame (mirrors SyncController.syncDown).
    state = BatchRunning(
      total: relPaths.length,
      done: 1,
      currentRelPath: relPaths.first,
      failures: const [],
    );
    try {
      final auth = await ref.read(authControllerProvider.future);
      if (auth is! AuthSignedIn) {
        state = _allFailed(relPaths, 'Sign in before importing specs.');
        return;
      }
      await _convertEach(relPaths, repo, workdir, auth.session.identity);
    } finally {
      _running = false;
    }
  }

  Future<void> _convertEach(
    List<String> relPaths,
    RepoRef repo,
    String workdir,
    GitIdentity identity,
  ) async {
    final importer = SpecImporter(
      fs: ref.read(fileSystemProvider),
      git: ref.read(gitPortProvider),
      clock: ref.read(clockProvider),
    );
    final converted = <JobRef>[];
    final failures = <BatchFailure>[];
    final reserved = <String>{};
    var cancelled = false;
    for (var i = 0; i < relPaths.length; i++) {
      if (_cancelRequested) {
        cancelled = true;
        break;
      }
      final relPath = relPaths[i];
      state = BatchRunning(
        total: relPaths.length,
        done: i + 1,
        currentRelPath: relPath,
        failures: List.unmodifiable(failures),
      );
      final outcome =
          await _convertOne(importer, relPath, repo, workdir, identity, reserved);
      switch (outcome) {
        case SpecImportSuccess(:final job):
          reserved.add(job.jobId);
          converted.add(job);
        case SpecImportFailure(:final message):
          failures.add(BatchFailure(relPath: relPath, message: message));
        case SpecImportCancelled():
          failures.add(BatchFailure(relPath: relPath, message: 'Cancelled.'));
      }
    }
    _finish(converted, failures, cancelled: cancelled);
  }

  void _finish(
    List<JobRef> converted,
    List<BatchFailure> failures, {
    required bool cancelled,
  }) {
    state = BatchFinished(
      converted: List.unmodifiable(converted),
      failures: List.unmodifiable(failures),
      cancelled: cancelled,
    );
    // Rediscover jobs + refresh the unpushed badge only when something was
    // actually committed (mirrors job_list_screen.dart:549-550).
    if (converted.isEmpty) return;
    ref.invalidate(jobListControllerProvider);
    ref.invalidate(pendingPushCountProvider);
  }

  Future<SpecImportOutcome> _convertOne(
    SpecImporter importer,
    String relPath,
    RepoRef repo,
    String workdir,
    GitIdentity identity,
    Set<String> reserved,
  ) async {
    try {
      return await importer.importFromRepoPath(
        sourceRelPath: relPath,
        repo: repo,
        workdir: workdir,
        identity: identity,
        reservedJobIds: reserved,
      );
    } catch (e) {
      return SpecImportFailure('Import failed: $e', cause: e);
    }
  }

  BatchFinished _allFailed(List<String> relPaths, String message) {
    return BatchFinished(
      converted: const [],
      failures: List.unmodifiable([
        for (final p in relPaths) BatchFailure(relPath: p, message: message),
      ]),
      cancelled: false,
    );
  }
}
