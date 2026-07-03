import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_controller.dart';
import 'package:gitmdscribe/app/controllers/batch_spec_importer.dart';
import 'package:gitmdscribe/app/providers/annotation_providers.dart';
import 'package:gitmdscribe/app/providers/auth_providers.dart';
import 'package:gitmdscribe/app/providers/spec_import_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/app/providers/sync_providers.dart';
import 'package:gitmdscribe/domain/entities/auth_session.dart';
import 'package:gitmdscribe/domain/entities/commit.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_clock.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/ports/git_port.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');
final _session = AuthSession(
  token: 'fake',
  identity: const GitIdentity(name: 'Alice', email: 'alice@example.com'),
);
final _fixedNow = DateTime.utc(2026, 4, 21, 10, 30);

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

/// Runs [onCommit] after each `commit` resolves. Lets a test drive a
/// cancel between the first and second file. Still records commits like
/// the base fake (and, crucially, never writes to the file system — the
/// AC-8 disk-blind property is inherited).
class _HookGitPort extends FakeGitPort {
  _HookGitPort(this.onCommit);
  final void Function(int commitIndex) onCommit;
  int _seen = 0;

  @override
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
    List<String> removals = const <String>[],
  }) async {
    final c = await super.commit(
      files: files,
      message: message,
      id: id,
      branch: branch,
      removals: removals,
    );
    onCommit(_seen++);
    return c;
  }
}

/// Counts `countCommitsAhead` invocations so a test can assert
/// [pendingPushCountProvider] was invalidated + recomputed (AC-9).
class _CountingGitPort extends FakeGitPort {
  int aheadCalls = 0;
  @override
  Future<int> countCommitsAhead({
    required String localBranch,
    required String remoteBranch,
  }) async {
    aheadCalls++;
    return super
        .countCommitsAhead(localBranch: localBranch, remoteBranch: remoteBranch);
  }
}

ProviderContainer _container({
  required FakeFileSystem fs,
  required FakeGitPort git,
  AuthState? auth,
  String workdir = '/repo',
}) {
  final resolvedAuth = auth ?? AuthSignedIn(_session);
  final c = ProviderContainer(overrides: [
    fileSystemProvider.overrideWithValue(fs),
    gitPortProvider.overrideWithValue(git),
    clockProvider.overrideWithValue(FakeClock(_fixedNow)),
    currentWorkdirProvider.overrideWith((_) => workdir),
    currentRepoProvider.overrideWith((_) => _repo),
    authControllerProvider.overrideWith(() => _StubAuthController(resolvedAuth)),
  ]);
  addTearDown(c.dispose);
  return c;
}

BatchConvertController _notifier(ProviderContainer c) =>
    c.read(batchConvertControllerProvider.notifier);

void main() {
  group('BatchConvertController.run', () {
    test('converts all selected — N files produce N commits (AC-4)', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/docs/a.md', '# A')
        ..seedFile('/repo/docs/b.md', '# B');
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git);
      await c.read(batchConvertControllerProvider.notifier).run(
        ['docs/a.md', 'docs/b.md'],
      );

      final state = c.read(batchConvertControllerProvider);
      expect(state, isA<BatchFinished>());
      final done = state as BatchFinished;
      expect(done.cancelled, isFalse);
      expect(done.failures, isEmpty);
      expect(done.converted.map((j) => j.jobId), ['spec-a', 'spec-b']);

      final log = git.commitLog('claude-jobs');
      expect(log.length, 2);
      expect(
        log.map((cmt) => cmt.message).toSet(),
        {'Import docs/a.md as spec-a', 'Import docs/b.md as spec-b'},
      );
    });

    test('skips a failing file and reports it (AC-6)', () async {
      // Middle file is not seeded -> FsNotFound -> SpecImportFailure.
      final fs = FakeFileSystem()
        ..seedFile('/repo/a.md', '# A')
        ..seedFile('/repo/c.md', '# C');
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git);
      await _notifier(c).run(['a.md', 'b.md', 'c.md']);

      final done = c.read(batchConvertControllerProvider) as BatchFinished;
      expect(done.converted.map((j) => j.jobId), ['spec-a', 'spec-c']);
      expect(done.failures.map((f) => f.relPath), ['b.md']);
      expect(done.cancelled, isFalse);
      // The loop did not abort early — both good files committed.
      expect(git.commitLog('claude-jobs').length, 2);
    });

    test('cancel stops after in-flight file (AC-7)', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/a.md', '# A')
        ..seedFile('/repo/b.md', '# B')
        ..seedFile('/repo/c.md', '# C');
      late BatchConvertController controller;
      final git = _HookGitPort((i) {
        if (i == 0) controller.cancel();
      });
      final c = _container(fs: fs, git: git);
      controller = _notifier(c);
      await controller.run(['a.md', 'b.md', 'c.md']);

      final done = c.read(batchConvertControllerProvider) as BatchFinished;
      expect(done.cancelled, isTrue);
      expect(done.converted.map((j) => j.jobId), ['spec-a']);
      // The two remaining files were never committed.
      expect(git.commitLog('claude-jobs').length, 1);
    });

    test('same-slug sources get distinct jobIds (AC-8)', () async {
      // Both slugify to `spec-notes`. FakeGitPort.commit does NOT write to
      // the fake FS, so the disk probe cannot see the first spec — only
      // the in-batch reservation keeps them apart.
      final fs = FakeFileSystem()
        ..seedFile('/repo/a/notes.md', '# one')
        ..seedFile('/repo/b/notes.md', '# two');
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git);
      await _notifier(c).run(['a/notes.md', 'b/notes.md']);

      final done = c.read(batchConvertControllerProvider) as BatchFinished;
      expect(done.converted.map((j) => j.jobId), ['spec-notes', 'spec-notes-2']);
      expect(git.commitLog('claude-jobs').length, 2);
    });

    test('signed out does nothing — zero commits, all failed (AC-10)',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/a.md', '# A')
        ..seedFile('/repo/b.md', '# B');
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git, auth: const AuthSignedOut());
      await _notifier(c).run(['a.md', 'b.md']);

      final done = c.read(batchConvertControllerProvider) as BatchFinished;
      expect(done.converted, isEmpty);
      expect(done.failures.map((f) => f.relPath), ['a.md', 'b.md']);
      expect(done.failures.first.message, contains('Sign in'));
      expect(git.branches, isEmpty, reason: 'no commit while signed out');
    });

    test('emits a determinate progress sequence done = 1..n (AC-5)', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/a.md', '# A')
        ..seedFile('/repo/b.md', '# B')
        ..seedFile('/repo/c.md', '# C');
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git);

      final running = <int>[];
      final sub = c.listen<BatchConvertState>(
        batchConvertControllerProvider,
        (_, next) {
          if (next is BatchRunning) {
            if (running.isEmpty || running.last != next.done) {
              running.add(next.done);
            }
            expect(next.total, 3);
          }
        },
      );
      await _notifier(c).run(['a.md', 'b.md', 'c.md']);
      sub.close();

      expect(running, [1, 2, 3]);
    });

    test('invalidates pendingPushCount on finish with conversions (AC-9)',
        () async {
      final fs = FakeFileSystem()..seedFile('/repo/a.md', '# A');
      final git = _CountingGitPort();
      final c = _container(fs: fs, git: git);
      // Keep the provider alive so invalidation triggers a recompute.
      c.listen(pendingPushCountProvider, (_, _) {});
      await c.read(pendingPushCountProvider.future);
      final before = git.aheadCalls;

      await _notifier(c).run(['a.md']);
      await c.read(pendingPushCountProvider.future);

      expect(git.aheadCalls, greaterThan(before),
          reason: 'terminal branch must invalidate pendingPushCountProvider');
    });

    test('empty selection is a no-op (stays BatchIdle)', () async {
      final fs = FakeFileSystem();
      final git = FakeGitPort();
      final c = _container(fs: fs, git: git);
      await _notifier(c).run(const []);
      expect(c.read(batchConvertControllerProvider), isA<BatchIdle>());
      expect(git.branches, isEmpty);
    });
  });
}
