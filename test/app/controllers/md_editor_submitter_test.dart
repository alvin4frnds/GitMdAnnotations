import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/md_editor_submitter.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';

const _identity = GitIdentity(name: 'Test User', email: 'test@example.com');

void main() {
  group('MdEditorSubmitter.submit', () {
    test('job-flow: commits on the requested claude-jobs branch with one '
        'FileWrite + "Edit <basename>" message', () async {
      final git = FakeGitPort();
      final submitter = MdEditorSubmitter(git: git);

      final commit = await submitter.submit(
        workdir: '/repo',
        absSpecPath: '/repo/jobs/pending/spec-foo/02-spec.md',
        newContents: '# new heading\n\nbody\n',
        identity: _identity,
        jobFlowBranch: 'claude-jobs',
      );

      expect(commit.message, 'Edit 02-spec.md');
      expect(commit.identity, _identity);
      final tree = git.branches['claude-jobs']!;
      expect(
        tree['jobs/pending/spec-foo/02-spec.md'],
        '# new heading\n\nbody\n',
      );
    });

    test('browser-flow: commits on the currently-checked-out branch '
        '(via GitPort.currentBranch)', () async {
      final git = FakeGitPort()..activeBranch = 'main';
      final submitter = MdEditorSubmitter(git: git);

      await submitter.submit(
        workdir: '/repo',
        absSpecPath: '/repo/docs/setup.md',
        newContents: 'edited',
        identity: _identity,
        jobFlowBranch: null, // browser flow
      );

      expect(git.branches['main']!['docs/setup.md'], 'edited');
      expect(git.branches['claude-jobs'], isNull);
    });

    test('strips workdir prefix to produce a repo-relative path', () async {
      final git = FakeGitPort();
      final submitter = MdEditorSubmitter(git: git);

      await submitter.submit(
        workdir: '/repo/nested/tree',
        absSpecPath: '/repo/nested/tree/deep/docs/spec.md',
        newContents: 'x',
        identity: _identity,
        jobFlowBranch: 'main',
      );

      final tree = git.branches['main']!;
      expect(tree.keys, contains('deep/docs/spec.md'));
      expect(tree.keys, isNot(contains('/repo/nested/tree/deep/docs/spec.md')));
    });

    test('normalizes Windows backslashes in the workdir and spec path',
        () async {
      final git = FakeGitPort();
      final submitter = MdEditorSubmitter(git: git);

      await submitter.submit(
        workdir: r'C:\repo',
        absSpecPath: r'C:\repo\docs\spec.md',
        newContents: 'win',
        identity: _identity,
        jobFlowBranch: 'main',
      );

      expect(git.branches['main']!['docs/spec.md'], 'win');
    });

    test('jobFlowBranch takes precedence over currentBranch when supplied',
        () async {
      final git = FakeGitPort()..activeBranch = 'feature/xyz';
      final submitter = MdEditorSubmitter(git: git);

      await submitter.submit(
        workdir: '/repo',
        absSpecPath: '/repo/jobs/pending/spec-foo/02-spec.md',
        newContents: 'job',
        identity: _identity,
        jobFlowBranch: 'claude-jobs',
      );

      expect(git.branches['claude-jobs'], isNotNull);
      expect(git.branches['feature/xyz'], isNull);
    });

    test('commit has no removals (pure single-file write)', () async {
      final git = FakeGitPort();
      final submitter = MdEditorSubmitter(git: git);

      final commit = await submitter.submit(
        workdir: '/repo',
        absSpecPath: '/repo/docs/spec.md',
        newContents: 'x',
        identity: _identity,
        jobFlowBranch: 'main',
      );

      expect(git.removalsOf(commit.sha), isEmpty);
    });
  });
}
