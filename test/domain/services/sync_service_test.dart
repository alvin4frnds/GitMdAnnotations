import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/git_port.dart';
import 'package:gitmdannotations_tablet/domain/services/sync_service.dart';

const _repo = RepoRef(owner: 'octocat', name: 'hello');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
const _workdir = '/tmp/work';

/// Subclass of [FakeGitPort] that records merge call order by target.
/// Far cheaper than a full proxy — the tests only care about sequencing
/// of mergeInto.
class _RecordingFake extends FakeGitPort {
  final List<String> merges = [];

  @override
  Future<void> mergeInto(String sourceBranch,
      {required String target}) async {
    merges.add('$sourceBranch->$target');
    return super.mergeInto(sourceBranch, target: target);
  }
}

Future<void> _seedMain(FakeGitPort git) async {
  await git.commit(
    files: const [FileWrite(path: 'README.md', contents: '# hi')],
    message: 'initial',
    id: _identity,
    branch: 'main',
  );
}

Future<void> _seedJobs(FakeGitPort git) async {
  await git.commit(
    files: const [FileWrite(path: '.keep', contents: '')],
    message: 'init-jobs',
    id: _identity,
    branch: 'claude-jobs',
  );
}

void main() {
  group('SyncService.syncDown', () {
    test('happy path with main already fast-forwarded emits full sequence',
        () async {
      final fake = _RecordingFake();
      await _seedMain(fake);
      await _seedJobs(fake);
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(
        events.map((e) => e.runtimeType.toString()).toList(),
        [
          'SyncStarted',
          'SyncFetching',
          'SyncFastForwardingMain',
          'SyncMergingMainIntoJobs',
          'SyncComplete',
        ],
      );
      expect(fake.fetchCount, 2);
      expect(fake.merges,
          containsAllInOrder(['origin/main->main', 'main->claude-jobs']));
    });

    test(
        'happy path with new main commits fast-forwards main then merges into jobs',
        () async {
      final fake = _RecordingFake()
        ..branches['origin/main'] = {'new.md': 'from remote'};
      await _seedMain(fake);
      await _seedJobs(fake);
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(events.last, isA<SyncComplete>());
      // origin/main content has propagated through main into claude-jobs.
      expect(fake.branches['main']!['new.md'], 'from remote');
      expect(fake.branches['claude-jobs']!['new.md'], 'from remote');
      expect(
        fake.merges.indexOf('origin/main->main'),
        lessThan(fake.merges.indexOf('main->claude-jobs')),
      );
    });

    test('no-op path (both branches current) still emits the full sequence',
        () async {
      final fake = FakeGitPort();
      await _seedMain(fake);
      await _seedJobs(fake);
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(events.whereType<SyncStarted>(), hasLength(1));
      expect(events.whereType<SyncFetching>(), isNotEmpty);
      expect(events.whereType<SyncFastForwardingMain>(), hasLength(1));
      expect(events.whereType<SyncMergingMainIntoJobs>(), hasLength(1));
      expect(events.last, isA<SyncComplete>());
    });

    test('main-merge conflict surfaces SyncFailed and does not emit Complete',
        () async {
      final fake = FakeGitPort();
      await _seedMain(fake);
      await _seedJobs(fake);
      fake.scriptNextMergeConflict = const ['README.md'];
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(events.last, isA<SyncFailed>());
      expect((events.last as SyncFailed).error, isA<GitMergeConflict>());
      expect(events.whereType<SyncComplete>(), isEmpty);
      expect(events.whereType<SyncMergingMainIntoJobs>(), isEmpty);
    });

    test('claude-jobs merge conflict surfaces SyncFailed', () async {
      final fake = _FailSecondMerge();
      await fake.commit(
        files: const [FileWrite(path: 'README.md', contents: '# hi')],
        message: 'initial',
        id: _identity,
        branch: 'main',
      );
      await fake.commit(
        files: const [FileWrite(path: '.keep', contents: '')],
        message: 'init-jobs',
        id: _identity,
        branch: 'claude-jobs',
      );
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(events.last, isA<SyncFailed>());
      expect((events.last as SyncFailed).error, isA<GitMergeConflict>());
      expect(events.whereType<SyncMergingMainIntoJobs>(), hasLength(1));
      expect(events.whereType<SyncComplete>(), isEmpty);
    });

    test('bootstrap: claude-jobs missing locally still completes', () async {
      final fake = FakeGitPort();
      await _seedMain(fake);
      // Deliberately NOT seeding claude-jobs.
      final service = SyncService(git: fake);

      final events = await service
          .syncDown(_repo, workdir: _workdir)
          .toList();

      expect(events.last, isA<SyncComplete>());
    });

    test('stream completes after SyncComplete (await for terminates)',
        () async {
      final fake = FakeGitPort();
      await _seedMain(fake);
      await _seedJobs(fake);
      final service = SyncService(git: fake);

      var seenComplete = false;
      await for (final p in service.syncDown(_repo, workdir: _workdir)) {
        if (p is SyncComplete) seenComplete = true;
      }
      expect(seenComplete, isTrue);
    });
  });
}

/// Throws [GitMergeConflict] only on the 2nd mergeInto (main->claude-jobs).
class _FailSecondMerge extends FakeGitPort {
  int _n = 0;
  @override
  Future<void> mergeInto(String s, {required String target}) async {
    if (++_n == 2) throw const GitMergeConflict(['README.md']);
    return super.mergeInto(s, target: target);
  }
}
