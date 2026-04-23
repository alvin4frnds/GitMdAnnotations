import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/job_deleter.dart';
import 'package:gitmdscribe/app/controllers/review_draft_store.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/job_ref.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';

const _repo = RepoRef(owner: 'acme', name: 'widgets');
final _job = JobRef(repo: _repo, jobId: 'spec-abc');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
const _workdir = '/workdir';

void main() {
  group('JobDeleter.delete', () {
    test(
      'happy path: commits removals for every file under '
      'jobs/pending/<jobId>/, drops them from the branch snapshot, and '
      'clears the review draft',
      () async {
        final fs = FakeFileSystem()
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/02-spec.md',
            '# spec',
          )
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/03-review.md',
            '# review',
          )
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/03-annotations.json',
            '{}',
          )
          // Seed a stale draft at the location ReviewDraftStore writes to.
          ..seedFile(
            '/docs/drafts/spec-abc/03-review.md.draft',
            '{"answers":{},"freeFormNotes":""}',
          )
          // Seed the claude-jobs branch so FakeGitPort has paths to strip.
          ..seedFile('$_workdir/jobs/pending/spec-other/02-spec.md', '# other');
        final git = FakeGitPort(initial: {
          'claude-jobs': {
            'jobs/pending/spec-abc/02-spec.md': '# spec',
            'jobs/pending/spec-abc/03-review.md': '# review',
            'jobs/pending/spec-abc/03-annotations.json': '{}',
            'jobs/pending/spec-other/02-spec.md': '# other',
          },
        });
        final drafts = ReviewDraftStore(fs);
        final deleter = JobDeleter(fs: fs, git: git, drafts: drafts);

        final outcome = await deleter.delete(
          job: _job,
          workdir: _workdir,
          id: _identity,
        );

        expect(outcome, isA<JobDeleteCommitted>());
        final commit = (outcome as JobDeleteCommitted).commit;
        expect(commit.message, 'delete: spec-abc');

        // Branch snapshot no longer contains the spec-abc paths…
        final tree = git.branches['claude-jobs']!;
        expect(tree.keys.any((p) => p.startsWith('jobs/pending/spec-abc/')),
            isFalse);
        // …and a sibling job is untouched.
        expect(tree['jobs/pending/spec-other/02-spec.md'], '# other');

        // Commit carries every under-folder path as removals.
        final recorded = git.removalsOf(commit.sha);
        expect(recorded, hasLength(3));
        expect(recorded, contains('jobs/pending/spec-abc/02-spec.md'));
        expect(recorded, contains('jobs/pending/spec-abc/03-review.md'));
        expect(recorded, contains('jobs/pending/spec-abc/03-annotations.json'));

        // Draft file is gone.
        expect(
          await fs.exists('/docs/drafts/spec-abc/03-review.md.draft'),
          isFalse,
        );
      },
    );

    test(
      'empty folder → returns JobDeleteNoop and does NOT touch git',
      () async {
        final fs = FakeFileSystem();
        final git = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
        final drafts = ReviewDraftStore(fs);
        final deleter = JobDeleter(fs: fs, git: git, drafts: drafts);

        final outcome = await deleter.delete(
          job: _job,
          workdir: _workdir,
          id: _identity,
        );

        expect(outcome, isA<JobDeleteNoop>());
        expect(git.commitLog('claude-jobs'), isEmpty);
      },
    );

    test(
      'enumerates files nested under sub-directories (e.g. annotations/)',
      () async {
        final fs = FakeFileSystem()
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/02-spec.md',
            '# spec',
          )
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/annotations/stroke-1.json',
            '{}',
          )
          ..seedFile(
            '$_workdir/jobs/pending/spec-abc/annotations/stroke-2.json',
            '{}',
          );
        final git = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
        final drafts = ReviewDraftStore(fs);
        final deleter = JobDeleter(fs: fs, git: git, drafts: drafts);

        final outcome = await deleter.delete(
          job: _job,
          workdir: _workdir,
          id: _identity,
        );

        expect(outcome, isA<JobDeleteCommitted>());
        final recorded =
            git.removalsOf((outcome as JobDeleteCommitted).commit.sha);
        expect(recorded, hasLength(3));
        expect(recorded,
            contains('jobs/pending/spec-abc/annotations/stroke-1.json'));
        expect(recorded,
            contains('jobs/pending/spec-abc/annotations/stroke-2.json'));
      },
    );

    test('commits on the claude-jobs branch with the signed-in identity',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$_workdir/jobs/pending/spec-abc/02-spec.md', '# spec');
      final git = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      final drafts = ReviewDraftStore(fs);
      final deleter = JobDeleter(fs: fs, git: git, drafts: drafts);

      await deleter.delete(
        job: _job,
        workdir: _workdir,
        id: _identity,
      );

      final log = git.commitLog('claude-jobs');
      expect(log, hasLength(1));
      expect(log.first.identity, _identity);
      expect(log.first.message, 'delete: spec-abc');
    });
  });
}
