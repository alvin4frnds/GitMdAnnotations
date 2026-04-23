import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/job_list_controller.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/entities/phase.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');

ProviderContainer _buildContainer({
  FakeFileSystem? fs,
  String? workdir,
  RepoRef? repo,
}) {
  final container = ProviderContainer(overrides: [
    fileSystemProvider.overrideWithValue(fs ?? FakeFileSystem()),
    if (workdir != null) currentWorkdirProvider.overrideWith((_) => workdir),
    if (repo != null) currentRepoProvider.overrideWith((_) => repo),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('JobListController.build()', () {
    test(
        'emits JobListLoaded with the resolved jobs for the current repo '
        'when workdir + repo are set', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', '# foo');

      final container = _buildContainer(
        fs: fs,
        workdir: '/repo',
        repo: _repo,
      );

      final state = await container.read(jobListControllerProvider.future);
      expect(state, isA<JobListLoaded>());
      final loaded = state as JobListLoaded;
      expect(loaded.jobs, hasLength(1));
      expect(loaded.jobs.single.ref.jobId, 'spec-foo');
      expect(loaded.jobs.single.phase, Phase.spec);
      expect(loaded.jobs.single.ref.repo, _repo);
    });

    test('emits JobListEmpty when no workdir is set', () async {
      final container = _buildContainer(repo: _repo);
      final state = await container.read(jobListControllerProvider.future);
      expect(state, isA<JobListEmpty>());
    });

    test('emits JobListEmpty when no repo is set', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', '# foo');
      final container = _buildContainer(fs: fs, workdir: '/repo');
      final state = await container.read(jobListControllerProvider.future);
      expect(state, isA<JobListEmpty>());
    });

    test('missing jobs/pending directory yields an empty JobListLoaded',
        () async {
      final container = _buildContainer(
        fs: FakeFileSystem(),
        workdir: '/repo',
        repo: _repo,
      );
      final state = await container.read(jobListControllerProvider.future);
      expect(state, isA<JobListLoaded>());
      expect((state as JobListLoaded).jobs, isEmpty);
    });
  });

  group('JobListController.refresh()', () {
    test('re-runs discovery and picks up newly-seeded jobs', () async {
      final fs = FakeFileSystem();
      final container = _buildContainer(
        fs: fs,
        workdir: '/repo',
        repo: _repo,
      );

      final first = await container.read(jobListControllerProvider.future);
      expect((first as JobListLoaded).jobs, isEmpty);

      fs.seedFile('/repo/jobs/pending/spec-foo/02-spec.md', '# foo');
      await container.read(jobListControllerProvider.notifier).refresh();

      final second = await container.read(jobListControllerProvider.future);
      expect(second, isA<JobListLoaded>());
      expect((second as JobListLoaded).jobs, hasLength(1));
    });
  });
}
