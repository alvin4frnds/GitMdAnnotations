import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/ports/file_system_port.dart';
import '../../domain/ports/git_port.dart';
import 'review_draft_store.dart';

/// Outcome of a [JobDeleter.delete] call. A missing or already-empty
/// `jobs/pending/<jobId>/` folder produces [JobDeleteNoop]; otherwise
/// the service returns [JobDeleteCommitted] with the fresh commit.
sealed class JobDeleteOutcome {
  const JobDeleteOutcome();
}

class JobDeleteCommitted extends JobDeleteOutcome {
  const JobDeleteCommitted(this.commit);
  final Commit commit;
}

class JobDeleteNoop extends JobDeleteOutcome {
  const JobDeleteNoop();
}

/// Domain service that deletes an entire `jobs/pending/<jobId>/` folder
/// from the workdir + git index and records it as a single commit on
/// the `claude-jobs` sidecar branch.
///
/// Pure Dart, no Flutter. The paired Riverpod provider lives in
/// `lib/app/providers/job_deleter_providers.dart`; the JobList long-press
/// handler calls `delete()` on this service.
///
/// Ordering: the git commit lands FIRST, draft-delete SECOND. If the
/// commit fails the draft survives so the user can retry a submit. If
/// the draft delete fails after a successful commit, the job is already
/// gone on the branch; the stale draft is cosmetic and gets garbage-
/// collected when the user next opens the review panel (the loader
/// tolerates missing / invalid drafts).
class JobDeleter {
  JobDeleter({
    required FileSystemPort fs,
    required GitPort git,
    required ReviewDraftStore drafts,
  })  : _fs = fs,
        _git = git,
        _drafts = drafts;

  final FileSystemPort _fs;
  final GitPort _git;
  final ReviewDraftStore _drafts;

  /// Removes `<workdir>/jobs/pending/<job.jobId>/` and every file under
  /// it in a single commit authored by [id] on `claude-jobs`. Returns
  /// [JobDeleteNoop] when the folder is missing or empty; callers map
  /// that to a user-facing "nothing to delete" rather than an error.
  Future<JobDeleteOutcome> delete({
    required JobRef job,
    required String workdir,
    required GitIdentity id,
  }) async {
    final folder = 'jobs/pending/${job.jobId}';
    final absFolder = '$workdir/$folder';
    final relPaths = await _enumerateFiles(absFolder, relativeTo: workdir);
    if (relPaths.isEmpty) return const JobDeleteNoop();
    final commit = await _git.commit(
      files: const <FileWrite>[],
      removals: relPaths,
      message: 'delete: ${job.jobId}',
      id: id,
      branch: 'claude-jobs',
    );
    // Drop the per-job review draft — best-effort; the commit is already
    // on the branch, and ReviewDraftStore.load() treats missing entries
    // as "no draft", so a stale file is harmless.
    await _drafts.delete(job);
    return JobDeleteCommitted(commit);
  }

  /// Walks [dir] recursively and returns every file path **relative to
  /// [relativeTo]** (no leading slash). Returns an empty list when the
  /// directory doesn't exist so the caller can short-circuit cleanly.
  Future<List<String>> _enumerateFiles(
    String dir, {
    required String relativeTo,
  }) async {
    if (!await _fs.exists(dir)) return const <String>[];
    final result = <String>[];
    await _walk(dir, result);
    final prefix = relativeTo.endsWith('/') ? relativeTo : '$relativeTo/';
    return [
      for (final abs in result)
        if (abs.startsWith(prefix)) abs.substring(prefix.length) else abs,
    ];
  }

  Future<void> _walk(String dir, List<String> out) async {
    final entries = await _fs.listDir(dir);
    for (final e in entries) {
      if (e.isDirectory) {
        await _walk(e.path, out);
      } else {
        out.add(e.path);
      }
    }
  }
}
