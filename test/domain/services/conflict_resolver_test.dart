import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/git_port.dart';
import 'package:gitmdannotations_tablet/domain/services/conflict_resolver.dart';

const _repo = RepoRef(owner: 'octocat', name: 'hello');
const _backupRoot = '/appdocs/backups/octocat-hello';

/// Subclass of [FakeGitPort] that records the exact sequence of GitPort
/// calls we care about for remote-wins archival — backupBranchHead,
/// resetHard, and mergeInto — mirroring the `_RecordingFake` pattern from
/// `sync_service_test.dart`.
class _RecordingFake extends FakeGitPort {
  final List<String> calls = [];

  @override
  Future<BackupRef> backupBranchHead(
    String branch, {
    required String backupRoot,
  }) {
    calls.add('backup:$branch@$backupRoot');
    return super.backupBranchHead(branch, backupRoot: backupRoot);
  }

  @override
  Future<void> fetch(RepoRef repo, {required String branch}) {
    calls.add('fetch:$branch');
    return super.fetch(repo, branch: branch);
  }

  @override
  Future<void> resetHard(String ref) {
    calls.add('reset:$ref');
    return super.resetHard(ref);
  }

  @override
  Future<void> mergeInto(String sourceBranch, {required String target}) {
    calls.add('merge:$sourceBranch->$target');
    return super.mergeInto(sourceBranch, target: target);
  }
}

void main() {
  group('ConflictResolver.archiveAndReset', () {
    test('calls backupBranchHead with claude-jobs and the given backupRoot',
        () async {
      final fake = _RecordingFake();
      final resolver = ConflictResolver(git: fake);

      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.calls.first, 'backup:claude-jobs@$_backupRoot');
    });

    test(
        'calls backup -> fetch claude-jobs + main -> reset -> merge in order',
        () async {
      final fake = _RecordingFake();
      final resolver = ConflictResolver(git: fake);

      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.calls, [
        'backup:claude-jobs@$_backupRoot',
        // Fetch is mandatory before reset: push only observed the remote
        // state over the protocol to detect NFF; refs/remotes/origin/*
        // locally is still the stale pre-push snapshot. Without this
        // fetch, resetHard resets to the stale local view and silently
        // drops any commits another device just pushed. Pinned by
        // integration_test/sync_conflict_test.dart.
        'fetch:claude-jobs',
        'fetch:main',
        'reset:origin/claude-jobs',
        'merge:origin/main->claude-jobs',
      ]);
    });

    test('merges origin/main into claude-jobs (last call)', () async {
      final fake = _RecordingFake();
      final resolver = ConflictResolver(git: fake);

      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.calls.last, 'merge:origin/main->claude-jobs');
    });

    test('returns the exact BackupRef produced by backupBranchHead', () async {
      final fake = FakeGitPort();
      final resolver = ConflictResolver(git: fake);

      final returned =
          await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(identical(returned, fake.backups.last), isTrue);
    });

    test('registers exactly one BackupRef per call', () async {
      final fake = FakeGitPort();
      final resolver = ConflictResolver(git: fake);

      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.backups, hasLength(1));
    });

    test(
        'propagates GitMergeConflict from the final mergeInto and still '
        'leaves the backup in place', () async {
      final fake = FakeGitPort()
        ..scriptNextMergeConflict = const ['README.md'];
      final resolver = ConflictResolver(git: fake);

      await expectLater(
        () => resolver.archiveAndReset(_repo, backupRoot: _backupRoot),
        throwsA(
          isA<GitMergeConflict>().having(
            (_) => fake.backups.length,
            'backup preserved after conflict',
            1,
          ),
        ),
      );
    });

    test(
        'post-state: local claude-jobs tree is origin/main merged on the '
        'reset origin/claude-jobs state', () async {
      // The fake's resetHard consults snapshots keyed by (branch, ref). We
      // must pre-seed a snapshot at 'origin/claude-jobs' on the
      // 'claude-jobs' branch — otherwise the fake falls back to its
      // "drop-latest-commit" heuristic and the assertion below becomes a
      // coincidence.
      final fake = FakeGitPort()
        ..branches['origin/claude-jobs'] = {'A.md': 'a', 'B.md': 'b'}
        ..branches['origin/main'] = {'A.md': 'a', 'C.md': 'c'}
        ..branches['claude-jobs'] = {'X.md': 'x', 'Y.md': 'y'};
      // Seed the "post-reset" tree that resetHard('origin/claude-jobs')
      // should restore: exactly what origin/claude-jobs holds right now.
      fake.branches['claude-jobs'] =
          Map<String, String>.from(fake.branches['origin/claude-jobs']!);
      fake.snapshotForRemote('origin/claude-jobs', branch: 'claude-jobs');
      // Put the stale local state back so resetHard has something to undo.
      fake.branches['claude-jobs'] = {'X.md': 'x', 'Y.md': 'y'};

      final resolver = ConflictResolver(git: fake);
      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.branches['claude-jobs'],
          {'A.md': 'a', 'B.md': 'b', 'C.md': 'c'});
    });

    test('cold operation — each call creates a fresh BackupRef', () async {
      final fake = FakeGitPort();
      final resolver = ConflictResolver(git: fake);

      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);
      await resolver.archiveAndReset(_repo, backupRoot: _backupRoot);

      expect(fake.backups, hasLength(2));
    });
  });
}
