import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/changelog_viewer_controller.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';

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
  group('ChangelogViewerController.build()', () {
    test('emits ChangelogViewerEmpty when no workdir is set', () async {
      final container = _buildContainer(repo: _repo);
      final state =
          await container.read(changelogViewerControllerProvider.future);
      expect(state, isA<ChangelogViewerEmpty>());
    });

    test('emits ChangelogViewerEmpty when no repo is set', () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/jobs/pending/spec-foo/02-spec.md',
          '# foo\n\n## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: foo\n',
        );
      final container = _buildContainer(fs: fs, workdir: '/repo');
      final state =
          await container.read(changelogViewerControllerProvider.future);
      expect(state, isA<ChangelogViewerEmpty>());
    });

    test(
        'emits ChangelogViewerLoaded with aggregated entries newest-first '
        'when workdir + repo are set', () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/jobs/pending/spec-alpha/02-spec.md',
          '# alpha\n\n## Changelog\n\n'
              '- 2026-04-18 09:00 desktop: alpha initial\n',
        )
        ..seedFile(
          '/repo/jobs/pending/spec-beta/02-spec.md',
          '# beta\n\n## Changelog\n\n'
              '- 2026-04-21 08:15 tablet: beta tightened\n',
        );

      final container = _buildContainer(
        fs: fs,
        workdir: '/repo',
        repo: _repo,
      );
      final state =
          await container.read(changelogViewerControllerProvider.future);
      expect(state, isA<ChangelogViewerLoaded>());
      final loaded = state as ChangelogViewerLoaded;
      expect(loaded.entries, hasLength(2));
      expect(loaded.entries.first.job.jobId, 'spec-beta');
      expect(loaded.entries.last.job.jobId, 'spec-alpha');
    });

    test(
        'no jobs on disk -> empty loaded state (not an error, not empty-state)',
        () async {
      final container = _buildContainer(
        fs: FakeFileSystem(),
        workdir: '/repo',
        repo: _repo,
      );
      final state =
          await container.read(changelogViewerControllerProvider.future);
      expect(state, isA<ChangelogViewerLoaded>());
      expect((state as ChangelogViewerLoaded).entries, isEmpty);
    });
  });

  group('ChangelogViewerController.refresh()', () {
    test('re-runs aggregation and picks up newly-seeded changelog entries',
        () async {
      final fs = FakeFileSystem();
      final container = _buildContainer(
        fs: fs,
        workdir: '/repo',
        repo: _repo,
      );

      final first =
          await container.read(changelogViewerControllerProvider.future);
      expect((first as ChangelogViewerLoaded).entries, isEmpty);

      fs.seedFile(
        '/repo/jobs/pending/spec-foo/02-spec.md',
        '# foo\n\n## Changelog\n\n'
            '- 2026-04-20 10:00 desktop: seeded after first build\n',
      );
      await container
          .read(changelogViewerControllerProvider.notifier)
          .refresh();

      final second =
          await container.read(changelogViewerControllerProvider.future);
      expect(second, isA<ChangelogViewerLoaded>());
      expect((second as ChangelogViewerLoaded).entries, hasLength(1));
      expect(second.entries.single.job.jobId, 'spec-foo');
    });
  });
}
