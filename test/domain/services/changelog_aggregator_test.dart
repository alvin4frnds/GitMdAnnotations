import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/services/changelog_aggregator.dart';
import 'package:gitmdannotations_tablet/domain/services/spec_repository.dart';

void main() {
  const repo = RepoRef(owner: 'octocat', name: 'hello-world');
  const workdir = '/repo';

  ChangelogAggregator build(FakeFileSystem fs) =>
      ChangelogAggregator(SpecRepository(fs: fs, workdir: workdir));

  group('ChangelogAggregator.allChangelogs', () {
    test('zero jobs -> empty list', () async {
      final fs = FakeFileSystem();
      expect(await build(fs).allChangelogs(repo), isEmpty);
    });

    test(
        'aggregates entries across multiple jobs and sorts newest-first',
        () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '$workdir/jobs/pending/spec-alpha/02-spec.md',
          '# alpha\n\n## Changelog\n\n'
              '- 2026-04-18 09:00 desktop: alpha initial draft\n'
              '- 2026-04-20 14:32 tablet: alpha clarified flow\n',
        )
        ..seedFile(
          '$workdir/jobs/pending/spec-beta/02-spec.md',
          '# beta\n\n## Changelog\n\n'
              '- 2026-04-19 12:00 desktop: beta initial draft\n'
              '- 2026-04-21 08:15 tablet: beta tightened scope\n',
        );

      final entries = await build(fs).allChangelogs(repo);

      // Four entries, newest first. The 04-21 beta entry leads; then
      // 04-20 alpha; then 04-19 beta; then 04-18 alpha.
      expect(entries, hasLength(4));
      expect(entries.map((e) => e.entry.description).toList(), [
        'beta tightened scope',
        'alpha clarified flow',
        'beta initial draft',
        'alpha initial draft',
      ]);
      expect(entries.map((e) => e.job.jobId).toList(), [
        'spec-beta',
        'spec-alpha',
        'spec-beta',
        'spec-alpha',
      ]);
    });

    test(
        'jobs without a changelog section are silently skipped (not an '
        'error)', () async {
      final fs = FakeFileSystem()
        // No `## Changelog` section at all.
        ..seedFile(
          '$workdir/jobs/pending/spec-empty/02-spec.md',
          '# empty spec\n\nBody without a changelog.\n',
        )
        // Has one entry.
        ..seedFile(
          '$workdir/jobs/pending/spec-has/02-spec.md',
          '# has changelog\n\n## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: only entry in the repo\n',
        );

      final entries = await build(fs).allChangelogs(repo);
      expect(entries, hasLength(1));
      expect(entries.single.job.jobId, 'spec-has');
      expect(entries.single.entry.author, 'desktop');
    });

    test(
        'a job with a malformed `## Changelog` section is skipped rather '
        'than bubbling the parse error', () async {
      final fs = FakeFileSystem()
        // Good job.
        ..seedFile(
          '$workdir/jobs/pending/spec-good/02-spec.md',
          '# good\n\n## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: good entry\n',
        )
        // Broken job — date field is missing the minute component, so
        // the strict regex in `parseChangelog` throws FormatException.
        ..seedFile(
          '$workdir/jobs/pending/spec-bad/02-spec.md',
          '# bad\n\n## Changelog\n\n'
              '- 2026-04-20 desktop: missing-time entry\n',
        );

      final entries = await build(fs).allChangelogs(repo);
      expect(entries, hasLength(1));
      expect(entries.single.job.jobId, 'spec-good');
    });

    test(
        'preserves insertion order among entries with identical timestamps',
        () async {
      // Two entries at the same minute in the same job — the aggregator
      // must not reshuffle them.
      final fs = FakeFileSystem()
        ..seedFile(
          '$workdir/jobs/pending/spec-tied/02-spec.md',
          '# tied\n\n## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: first\n'
              '- 2026-04-20 10:00 tablet: second\n',
        );

      final entries = await build(fs).allChangelogs(repo);
      expect(entries.map((e) => e.entry.description).toList(),
          ['first', 'second']);
    });

    test('result is unmodifiable (callers cannot mutate the shared list)',
        () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '$workdir/jobs/pending/spec-x/02-spec.md',
          '# x\n\n## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: x\n',
        );
      final entries = await build(fs).allChangelogs(repo);
      expect(() => entries.add(entries.first), throwsUnsupportedError);
    });
  });
}
