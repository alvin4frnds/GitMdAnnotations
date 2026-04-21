import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job.dart';
import '../../domain/entities/repo_ref.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';

/// Sealed UI-level state for the Job List screen. Exhaustive `switch` in
/// widgets. See IMPLEMENTATION.md §4.3.
sealed class JobListState {
  const JobListState();
}

/// No repo picked yet — empty workdir or `currentRepoProvider` unset. The
/// screen chrome stays visible but the list is a muted empty state.
class JobListEmpty extends JobListState {
  const JobListEmpty();
}

/// One [Job] per `jobs/pending/spec-*/` folder resolved via
/// [SpecRepository.listOpenJobs].
class JobListLoaded extends JobListState {
  const JobListLoaded(this.jobs);
  final List<Job> jobs;
}

/// Wires [SpecRepository] into a Riverpod `AsyncNotifier`. Rebuilt whenever
/// [currentWorkdirProvider] or [currentRepoProvider] changes so that the
/// RepoPicker in M1c can flip the source without us caring.
///
/// Also takes responsibility for ensuring the `GitPort` isolate has the
/// restored repo open before any downstream screen tries to commit
/// (review submit / approve / sync). The NFR-2 cold-start preload only
/// restores `currentRepoProvider` + `currentWorkdirProvider` from
/// SecureStorage — it bypasses RepoPicker, which is the only other place
/// that calls `gitPort.cloneOrOpen`. Without this warm-up, Submit Review
/// fails with "GitAdapter: no repository open — call cloneOrOpen first".
class JobListController extends AsyncNotifier<JobListState> {
  @override
  Future<JobListState> build() async {
    final repo = ref.watch(currentRepoProvider);
    final workdir = ref.watch(currentWorkdirProvider);
    final spec = ref.watch(specRepositoryProvider);
    if (repo == null || spec == null || workdir == null) {
      return const JobListEmpty();
    }
    await _ensureRepoOpen(repo, workdir);
    final jobs = await spec.listOpenJobs(repo);
    return JobListLoaded(jobs);
  }

  /// Calls `gitPort.cloneOrOpen` so Submit / Approve / Sync can talk to
  /// the libgit2 isolate. Failures are logged and swallowed — the JobList
  /// still renders from disk even if git isn't ready, and the downstream
  /// operation will surface its own error when the user tries it.
  Future<void> _ensureRepoOpen(RepoRef repo, String workdir) async {
    try {
      await ref.read(gitPortProvider).cloneOrOpen(repo, workdir: workdir);
    } catch (e) {
      developer.log(
        'JobListController: cloneOrOpen warm-up failed — Submit/Sync may fail '
        'until the user re-picks the repo',
        name: 'gitmdscribe.job_list',
        error: e,
      );
    }
  }

  /// Re-runs discovery. Transitions state through `loading` so the UI can
  /// show a spinner. Errors are captured by [AsyncValue.guard].
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }
}
