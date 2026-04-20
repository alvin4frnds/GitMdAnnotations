import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job.dart';
import '../providers/spec_providers.dart';

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
class JobListController extends AsyncNotifier<JobListState> {
  @override
  Future<JobListState> build() async {
    final repo = ref.watch(currentRepoProvider);
    final spec = ref.watch(specRepositoryProvider);
    if (repo == null || spec == null) return const JobListEmpty();
    final jobs = await spec.listOpenJobs(repo);
    return JobListLoaded(jobs);
  }

  /// Re-runs discovery. Transitions state through `loading` so the UI can
  /// show a spinner. Errors are captured by [AsyncValue.guard].
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }
}
