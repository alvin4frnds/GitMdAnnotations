import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/ports/git_port.dart';

void main() {
  const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
  const repo = RepoRef(owner: 'octocat', name: 'hello-world');

  group('FakeGitPort — cloneOrOpen / fetch', () {
    test('cloneOrOpen flips cloned flag', () async {
      final fake = FakeGitPort();
      expect(fake.cloned, isFalse);
      await fake.cloneOrOpen(repo, workdir: '/tmp/work');
      expect(fake.cloned, isTrue);
    });

    test('fetch increments the fetch counter', () async {
      final fake = FakeGitPort();
      expect(fake.fetchCount, 0);
      await fake.fetch(repo, branch: 'main');
      await fake.fetch(repo, branch: 'claude-jobs');
      expect(fake.fetchCount, 2);
    });
  });

  group('FakeGitPort — commit', () {
    test('atomic commit writes all files and appends one log entry', () async {
      final fake = FakeGitPort(initial: {
        'claude-jobs': {'README.md': 'hi'},
      });
      final writes = [
        const FileWrite(path: 'jobs/pending/spec-x/03-review.md', contents: 'r'),
        const FileWrite(path: 'jobs/pending/spec-x/03-annotations.svg', contents: 's'),
        const FileWrite(path: 'jobs/pending/spec-x/03-annotations.png', contents: 'p'),
      ];

      final commit = await fake.commit(
        files: writes,
        message: 'review: spec-x',
        id: identity,
        branch: 'claude-jobs',
      );

      expect(commit.message, 'review: spec-x');
      expect(commit.identity, identity);
      expect(fake.branches['claude-jobs']!['jobs/pending/spec-x/03-review.md'], 'r');
      expect(fake.branches['claude-jobs']!['jobs/pending/spec-x/03-annotations.svg'], 's');
      expect(fake.branches['claude-jobs']!['jobs/pending/spec-x/03-annotations.png'], 'p');
      expect(fake.commitLog('claude-jobs'), hasLength(1));
      expect(fake.commitLog('claude-jobs').first.sha, commit.sha);
    });

    test('passes the commit message through verbatim', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      final commit = await fake.commit(
        files: const [FileWrite(path: 'a.md', contents: 'x')],
        message: 'approve: spec-42',
        id: identity,
        branch: 'claude-jobs',
      );
      expect(commit.message, 'approve: spec-42');
    });
  });

  group('FakeGitPort — commit preserves bytes (T7 widening)', () {
    test('FileWrite.bytes round-trips into binaryBranches verbatim',
        () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      final png = Uint8List.fromList(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01,
      ]);
      await fake.commit(
        files: [
          const FileWrite(
            path: 'jobs/pending/spec-x/03-review.md',
            contents: 'r',
          ),
          FileWrite(
            path: 'jobs/pending/spec-x/03-annotations.png',
            contents: '',
            bytes: png,
          ),
        ],
        message: 'review: spec-x',
        id: identity,
        branch: 'claude-jobs',
      );

      expect(
        fake.binaryBranches['claude-jobs']![
            'jobs/pending/spec-x/03-annotations.png'],
        png,
      );
    });
  });

  group('FakeGitPort — mergeInto', () {
    test('copies files from source to target (last-write-wins)', () async {
      final fake = FakeGitPort(initial: {
        'main': {'jobs/pending/spec-x/02-spec.md': 'spec body'},
        'claude-jobs': {'README.md': 'hi'},
      });

      await fake.mergeInto('main', target: 'claude-jobs');

      expect(
        fake.branches['claude-jobs']!['jobs/pending/spec-x/02-spec.md'],
        'spec body',
      );
      expect(fake.branches['claude-jobs']!['README.md'], 'hi');
    });

    test('scripted conflict throws GitMergeConflict once then clears',
        () async {
      final fake = FakeGitPort(initial: {
        'main': {'a/b.md': 'm'},
        'claude-jobs': {'a/b.md': 'cj'},
      })
        ..scriptNextMergeConflict = ['a/b.md'];

      await expectLater(
        fake.mergeInto('main', target: 'claude-jobs'),
        throwsA(isA<GitMergeConflict>().having(
          (e) => e.conflictedPaths,
          'conflictedPaths',
          ['a/b.md'],
        )),
      );

      // Second call succeeds — script was one-shot.
      await fake.mergeInto('main', target: 'claude-jobs');
      expect(fake.branches['claude-jobs']!['a/b.md'], 'm');
    });
  });

  group('FakeGitPort — push', () {
    test('default returns PushSuccess with current head sha', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      await fake.commit(
        files: const [FileWrite(path: 'x.md', contents: 'x')],
        message: 'review: spec-x',
        id: identity,
        branch: 'claude-jobs',
      );
      final head = await fake.headSha('claude-jobs');

      final outcome = await fake.push(repo, branch: 'claude-jobs');

      expect(outcome, isA<PushSuccess>());
      expect((outcome as PushSuccess).sha, head);
    });

    test('scripted non-fast-forward rejection returns typed outcome',
        () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}})
        ..scriptedPushOutcome = const PushRejectedNonFastForward(
          remoteSha: 'r',
          localSha: 'l',
        );

      final outcome = await fake.push(repo, branch: 'claude-jobs');
      expect(outcome, isA<PushRejectedNonFastForward>());
      final rej = outcome as PushRejectedNonFastForward;
      expect(rej.remoteSha, 'r');
      expect(rej.localSha, 'l');
    });

    test('scripted auth rejection returns PushRejectedAuth', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}})
        ..scriptedPushOutcome = const PushRejectedAuth();
      final outcome = await fake.push(repo, branch: 'claude-jobs');
      expect(outcome, isA<PushRejectedAuth>());
    });
  });

  group('FakeGitPort — resetHard', () {
    test('resetHard to scripted remoteSha restores snapshot', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      // Take a snapshot representing the remote head.
      await fake.commit(
        files: const [FileWrite(path: 'remote.md', contents: 'from remote')],
        message: 'baseline',
        id: identity,
        branch: 'claude-jobs',
      );
      final remoteHead = (await fake.headSha('claude-jobs'))!;
      fake.snapshotForRemote(remoteHead, branch: 'claude-jobs');

      // Make local drift (would be rejected on push).
      await fake.commit(
        files: const [FileWrite(path: 'local.md', contents: 'unsynced')],
        message: 'local work',
        id: identity,
        branch: 'claude-jobs',
      );
      fake.scriptedPushOutcome = PushRejectedNonFastForward(
        remoteSha: remoteHead,
        localSha: (await fake.headSha('claude-jobs'))!,
      );
      final pushed = await fake.push(repo, branch: 'claude-jobs');
      expect(pushed, isA<PushRejectedNonFastForward>());

      await fake.resetHard(remoteHead);

      expect(await fake.headSha('claude-jobs'), remoteHead);
      expect(fake.branches['claude-jobs']!['remote.md'], 'from remote');
      expect(fake.branches['claude-jobs']!.containsKey('local.md'), isFalse);
    });

    test('resetHard with no scripted snapshot removes the top commit',
        () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      await fake.commit(
        files: const [FileWrite(path: 'a.md', contents: 'a')],
        message: 'c1',
        id: identity,
        branch: 'claude-jobs',
      );
      await fake.commit(
        files: const [FileWrite(path: 'b.md', contents: 'b')],
        message: 'c2',
        id: identity,
        branch: 'claude-jobs',
      );
      final firstSha = fake.commitLog('claude-jobs').last.sha;

      await fake.resetHard('HEAD~1');

      expect(fake.commitLog('claude-jobs'), hasLength(1));
      expect((await fake.headSha('claude-jobs'))!, firstSha);
    });
  });

  group('FakeGitPort — backupBranchHead', () {
    test('records backup with injected clock timestamp and head sha',
        () async {
      final fixed = DateTime.utc(2026, 4, 20, 14, 32);
      final fake = FakeGitPort(
        initial: {'claude-jobs': <String, String>{}},
        clock: () => fixed,
      );
      await fake.commit(
        files: const [FileWrite(path: 'a.md', contents: 'a')],
        message: 'c1',
        id: identity,
        branch: 'claude-jobs',
      );
      final head = (await fake.headSha('claude-jobs'))!;

      final backup = await fake.backupBranchHead(
        'claude-jobs',
        backupRoot: '/app/backups/hello-world',
      );

      expect(backup.commitSha, head);
      expect(backup.createdAt, fixed);
      expect(backup.path.startsWith('/app/backups/hello-world/claude-jobs-'),
          isTrue);
      expect(fake.backups, hasLength(1));
      expect(fake.backups.single, backup);
    });
  });

  group('FakeGitPort — readChangelog', () {
    test('parses well-formed entries in file order', () async {
      final fake = FakeGitPort(initial: {
        'claude-jobs': {
          '02-spec.md': '# Spec\n\nBody.\n\n## Changelog\n\n'
              '- 2026-04-20 14:32 tablet: Clarified auth flow — TOTP required.\n'
              '- 2026-04-20 16:05 desktop: Revised to v2.\n',
        },
      });

      final entries = await fake.readChangelog('02-spec.md');

      expect(entries, hasLength(2));
      expect(entries[0].timestamp, DateTime(2026, 4, 20, 14, 32));
      expect(entries[0].author, 'tablet');
      expect(entries[0].description,
          'Clarified auth flow — TOTP required.');
      expect(entries[1].timestamp, DateTime(2026, 4, 20, 16, 5));
      expect(entries[1].author, 'desktop');
      expect(entries[1].description, 'Revised to v2.');
    });

    test('malformed entry throws FormatException', () async {
      final fake = FakeGitPort(initial: {
        'claude-jobs': {
          '02-spec.md': '## Changelog\n\n- 2026-14-40 99:99 tablet: nope\n',
        },
      });

      await expectLater(
        fake.readChangelog('02-spec.md'),
        throwsFormatException,
      );
    });

    test('no changelog section returns empty list', () async {
      final fake = FakeGitPort(initial: {
        'claude-jobs': {
          '02-spec.md': '# Spec\n\nJust a body, no changelog.\n',
        },
      });
      final entries = await fake.readChangelog('02-spec.md');
      expect(entries, isEmpty);
    });

    test('missing file returns empty list', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      final entries = await fake.readChangelog('nope.md');
      expect(entries, isEmpty);
    });
  });

  group('FakeGitPort — branch/head introspection', () {
    test('localBranches reflects the model', () async {
      final fake = FakeGitPort(initial: {
        'main': <String, String>{},
        'claude-jobs': <String, String>{},
      });
      final branches = await fake.localBranches();
      expect(branches.toSet(), {'main', 'claude-jobs'});
    });

    test('headSha returns the top commit sha for a branch', () async {
      final fake = FakeGitPort(initial: {'claude-jobs': <String, String>{}});
      await fake.commit(
        files: const [FileWrite(path: 'x.md', contents: 'x')],
        message: 'c1',
        id: identity,
        branch: 'claude-jobs',
      );
      final head = await fake.headSha('claude-jobs');
      expect(head, isNotNull);
      expect(head, fake.commitLog('claude-jobs').first.sha);
    });

    test('headSha of unknown branch returns null', () async {
      final fake = FakeGitPort();
      expect(await fake.headSha('nope'), isNull);
    });
  });

  group('GitError hierarchy', () {
    test('every concrete error is a GitError', () {
      expect(const GitMergeConflict(['a']), isA<GitError>());
      expect(const GitDirtyWorkingTree(), isA<GitError>());
      expect(const GitCorrupted('bad'), isA<GitError>());
      expect(GitNetworkFailure(Exception('x')), isA<GitError>());
    });
  });
}
