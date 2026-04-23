import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_controller.dart';
import 'package:gitmdscribe/app/controllers/sync_controller.dart';
import 'package:gitmdscribe/app/providers/annotation_providers.dart';
import 'package:gitmdscribe/app/providers/auth_providers.dart';
import 'package:gitmdscribe/app/providers/sync_providers.dart';
import 'package:gitmdscribe/domain/entities/auth_session.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_auth_port.dart';
import 'package:gitmdscribe/domain/fakes/fake_clock.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdscribe/domain/ports/git_port.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';
import 'package:gitmdscribe/domain/services/sync_service.dart';

const _repo = RepoRef(owner: 'octocat', name: 'hello');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
const _workdir = '/tmp/work';

Future<FakeGitPort> _seeded() async {
  final fake = FakeGitPort();
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
  return fake;
}

final _fixedNow = DateTime.utc(2026, 4, 21, 12, 0, 0);

({ProviderContainer container, FakeGitPort git}) _buildContainer(
  FakeGitPort git, {
  DateTime? at,
  FakeAuthPort? auth,
  FakeSecureStorage? storage,
}) {
  final a = auth ?? FakeAuthPort();
  final s = storage ?? FakeSecureStorage();
  final container = ProviderContainer(overrides: [
    gitPortProvider.overrideWithValue(git),
    clockProvider.overrideWithValue(FakeClock(at ?? _fixedNow)),
    authPortProvider.overrideWithValue(a),
    secureStorageProvider.overrideWithValue(s),
  ]);
  addTearDown(container.dispose);
  return (container: container, git: git);
}

/// Variant used to trigger a SyncFailed terminal state.
class _FailFirstMerge extends FakeGitPort {
  @override
  Future<void> mergeInto(String sourceBranch,
      {required String target}) async {
    throw const GitMergeConflict(['README.md']);
  }
}

void main() {
  group('SyncController.build()', () {
    test('initial build returns SyncIdle', () async {
      final fake = await _seeded();
      final env = _buildContainer(fake);
      final state = await env.container.read(syncControllerProvider.future);
      expect(state, isA<SyncIdle>());
    });
  });

  group('SyncController.syncDown', () {
    test('happy path transitions Idle -> InProgress(*) -> Done', () async {
      final fake = await _seeded();
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      final seen = <SyncState>[];
      final sub = env.container.listen<AsyncValue<SyncState>>(
        syncControllerProvider,
        (prev, next) => next.whenData(seen.add),
      );

      await env.container
          .read(syncControllerProvider.notifier)
          .syncDown(repo: _repo, workdir: _workdir);

      sub.close();

      expect(seen.whereType<SyncInProgress>(), isNotEmpty);
      expect(seen.last, isA<SyncDone>());
      expect(fake.fetchCount, 2);
    });

    test('failure path ends at SyncErrored', () async {
      final fake = _FailFirstMerge();
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
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      await env.container
          .read(syncControllerProvider.notifier)
          .syncDown(repo: _repo, workdir: _workdir);

      final state = env.container.read(syncControllerProvider).value;
      expect(state, isA<SyncErrored>());
      expect((state as SyncErrored).error, isA<GitMergeConflict>());
    });

    test('re-entrance while running does not double-run', () async {
      final fake = await _seeded();
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      final notifier = env.container.read(syncControllerProvider.notifier);
      final first = notifier.syncDown(repo: _repo, workdir: _workdir);
      final second = notifier.syncDown(repo: _repo, workdir: _workdir);
      await Future.wait<void>([first, second]);

      expect(fake.fetchCount, 2);
      final state = env.container.read(syncControllerProvider).value;
      expect(state, isA<SyncDone>());
    });
  });

  group('SyncController.syncUp', () {
    const backupRoot = '/tmp/backups';

    test('happy path transitions InProgress(*) -> SyncDone', () async {
      final fake = await _seeded();
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      final seen = <SyncState>[];
      final sub = env.container.listen<AsyncValue<SyncState>>(
        syncControllerProvider,
        (prev, next) => next.whenData(seen.add),
      );

      await env.container.read(syncControllerProvider.notifier).syncUp(
            repo: _repo,
            workdir: _workdir,
            backupRoot: backupRoot,
          );

      sub.close();

      expect(seen.whereType<SyncInProgress>(), isNotEmpty);
      expect(seen.last, isA<SyncDone>());
    });

    test('conflict flow surfaces SyncConflictArchived through SyncInProgress',
        () async {
      final fake = await _seeded();
      fake.scriptedPushOutcome = const PushRejectedNonFastForward(
        remoteSha: 'r',
        localSha: 'l',
      );
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      final seen = <SyncState>[];
      final sub = env.container.listen<AsyncValue<SyncState>>(
        syncControllerProvider,
        (prev, next) => next.whenData(seen.add),
      );

      await env.container.read(syncControllerProvider.notifier).syncUp(
            repo: _repo,
            workdir: _workdir,
            backupRoot: backupRoot,
          );

      sub.close();

      final archivedPhases = seen
          .whereType<SyncInProgress>()
          .where((s) => s.latest is SyncConflictArchived);
      expect(archivedPhases, hasLength(1));
      expect(seen.last, isA<SyncDone>());
    });

    test('SyncDone.backup carries the archived BackupRef after conflict flow',
        () async {
      final fake = await _seeded();
      fake.scriptedPushOutcome = const PushRejectedNonFastForward(
        remoteSha: 'r',
        localSha: 'l',
      );
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      await env.container.read(syncControllerProvider.notifier).syncUp(
            repo: _repo,
            workdir: _workdir,
            backupRoot: backupRoot,
          );

      final state = env.container.read(syncControllerProvider).value;
      expect(state, isA<SyncDone>());
      expect((state as SyncDone).backup, isNotNull);
    });

    test('PushRejectedAuth transitions to SyncErrored(PushRejectedAuth)',
        () async {
      final fake = await _seeded();
      fake.scriptedPushOutcome = const PushRejectedAuth();
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      await env.container.read(syncControllerProvider.notifier).syncUp(
            repo: _repo,
            workdir: _workdir,
            backupRoot: backupRoot,
          );

      final state = env.container.read(syncControllerProvider).value;
      expect(state, isA<SyncErrored>());
      expect((state as SyncErrored).error, isA<PushRejectedAuth>());
    });

    test(
      'PushRejectedAuth also invokes AuthController.handleTokenRevoked — '
      'auth flips to SignedOut and secure storage is cleared (W5.3 recovery)',
      () async {
        // Arrange: signed-in auth with a persisted token + identity.
        const session = AuthSession(
          token: 'tok-soon-to-be-revoked',
          identity: _identity,
        );
        final auth = FakeAuthPort()..storedSession = session;
        final storage = FakeSecureStorage();
        await storage.writeString(
          SecureStorageKeys.authToken,
          session.token,
        );
        await storage.writeString(
          SecureStorageKeys.gitIdentity,
          '{"name":"Ada","email":"ada@example.com"}',
        );
        final fake = await _seeded();
        fake.scriptedPushOutcome = const PushRejectedAuth();

        final env = _buildContainer(fake, auth: auth, storage: storage);
        // Prime AuthController so it reads its initial SignedIn state.
        await env.container.read(authControllerProvider.future);
        await env.container.read(syncControllerProvider.future);

        // Act.
        await env.container.read(syncControllerProvider.notifier).syncUp(
              repo: _repo,
              workdir: _workdir,
              backupRoot: backupRoot,
            );
        // Let the fire-and-forget handleTokenRevoked() finish.
        await Future<void>.delayed(Duration.zero);

        // Assert: auth is now SignedOut and the auth storage keys are gone.
        final authState = env.container.read(authControllerProvider).value;
        expect(authState, isA<AuthSignedOut>());
        expect(
          await storage.containsKey(SecureStorageKeys.authToken),
          isFalse,
        );
        expect(
          await storage.containsKey(SecureStorageKeys.gitIdentity),
          isFalse,
        );
        // Sync state still reflects the error so the UI can render a banner.
        final syncState = env.container.read(syncControllerProvider).value;
        expect(syncState, isA<SyncErrored>());
      },
    );

    test('re-entrance while running does not double-run', () async {
      final fake = await _seeded();
      final env = _buildContainer(fake);
      await env.container.read(syncControllerProvider.future);

      final notifier = env.container.read(syncControllerProvider.notifier);
      final first = notifier.syncUp(
        repo: _repo,
        workdir: _workdir,
        backupRoot: backupRoot,
      );
      final second = notifier.syncUp(
        repo: _repo,
        workdir: _workdir,
        backupRoot: backupRoot,
      );
      await Future.wait<void>([first, second]);

      // Only the first call archives anything (none in happy path), but
      // we can assert the outcome settled exactly once.
      final state = env.container.read(syncControllerProvider).value;
      expect(state, isA<SyncDone>());
    });
  });
}
