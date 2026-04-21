import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_controller.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_identity_codec.dart';
import 'package:gitmdannotations_tablet/app/controllers/repo_picker_controller.dart';
import 'package:gitmdannotations_tablet/app/last_session.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/repo_picker_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/sync_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/github_repo.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_github_repos_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/github_repos_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/secure_storage_port.dart';

const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');

const _repoA = GitHubRepo(
  owner: 'octocat',
  name: 'hello-world',
  defaultBranch: 'main',
  isPrivate: false,
);
const _repoB = GitHubRepo(
  owner: 'octocat',
  name: 'secret-plans',
  defaultBranch: 'master',
  isPrivate: true,
);

/// Builds a ProviderContainer with the auth controller pre-seeded to
/// [AuthSignedIn(_session)] by storing a token + identity blob in the
/// fake secure storage. This matches the real-app restore path — tests
/// exercise what the user sees after a hot restart, not mid-flow.
({
  ProviderContainer container,
  FakeGitHubReposPort repos,
  FakeGitPort git,
  FakeSecureStorage storage,
  Directory docsDir,
}) _buildContainer({
  FakeGitHubReposPort? repos,
  FakeGitPort? git,
  bool signedIn = true,
  String token = 'gho_test',
  GitIdentity identity = _identity,
  Directory? docsDir,
}) {
  final repos0 = repos ?? FakeGitHubReposPort();
  final git0 = git ?? FakeGitPort();
  final storage = FakeSecureStorage();
  // Docs dir override: pick() reads this via docsDirectoryProvider so we
  // don't hit path_provider's platform channel (which throws
  // MissingPluginException under `fvm flutter test`).
  final docs = docsDir ??
      Directory.systemTemp.createTempSync('repo-picker-test-docs-');
  addTearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });
  if (signedIn) {
    storage
      ..writeString(SecureStorageKeys.authToken, token)
      ..writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(identity),
      );
  }
  final container = ProviderContainer(overrides: [
    gitHubReposPortProvider.overrideWithValue(repos0),
    gitPortProvider.overrideWithValue(git0),
    authPortProvider.overrideWithValue(FakeAuthPort()),
    secureStorageProvider.overrideWithValue(storage),
    docsDirectoryProvider.overrideWithValue(() async => docs),
  ]);
  addTearDown(container.dispose);
  return (
    container: container,
    repos: repos0,
    git: git0,
    storage: storage,
    docsDir: docs,
  );
}

Future<void> _primeAuthSignedIn(ProviderContainer c) async {
  final state = await c.read(authControllerProvider.future);
  expect(state, isA<AuthSignedIn>(),
      reason: 'auth must be signed in for the picker happy path');
}

void main() {
  group('RepoPickerController.build()', () {
    test('AuthSignedOut → RepoPickerAuthError ("not signed in")', () async {
      final env = _buildContainer(signedIn: false);
      final authState = await env.container.read(authControllerProvider.future);
      expect(authState, isA<AuthSignedOut>());

      final state =
          await env.container.read(repoPickerControllerProvider.future);
      expect(state, isA<RepoPickerAuthError>());
      expect((state as RepoPickerAuthError).message, 'not signed in');
    });

    test(
        'AuthSignedIn + seeded repos → RepoPickerLoaded with the same '
        'list, port received the session token', () async {
      final repos = FakeGitHubReposPort(seededRepos: [_repoA, _repoB]);
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final state =
          await env.container.read(repoPickerControllerProvider.future);

      expect(state, isA<RepoPickerLoaded>());
      expect((state as RepoPickerLoaded).repos, [_repoA, _repoB]);
      expect(repos.tokensReceived, ['gho_test'],
          reason: 'auth session token must be threaded through the port');
    });

    test('AuthSignedIn + empty GitHub response → Loaded with empty list',
        () async {
      final repos = FakeGitHubReposPort();
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final state =
          await env.container.read(repoPickerControllerProvider.future);
      expect(state, isA<RepoPickerLoaded>());
      expect((state as RepoPickerLoaded).repos, isEmpty);
    });

    test('port throws GitHubReposAuthError → RepoPickerAuthError', () async {
      final repos = FakeGitHubReposPort()
        ..scriptError(const GitHubReposAuthError('401: token expired'));
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final state =
          await env.container.read(repoPickerControllerProvider.future);
      expect(state, isA<RepoPickerAuthError>());
      expect((state as RepoPickerAuthError).message, contains('401'));
    });

    test('port throws GitHubReposNetworkError → RepoPickerNetworkError',
        () async {
      final repos = FakeGitHubReposPort()
        ..scriptError(const GitHubReposNetworkError('connection refused'));
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final state =
          await env.container.read(repoPickerControllerProvider.future);
      expect(state, isA<RepoPickerNetworkError>());
      expect((state as RepoPickerNetworkError).message,
          contains('connection refused'));
    });
  });

  group('RepoPickerController.refresh()', () {
    test('re-runs the list fetch and picks up newly-seeded repos', () async {
      final repos = FakeGitHubReposPort();
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final initial =
          await env.container.read(repoPickerControllerProvider.future);
      expect((initial as RepoPickerLoaded).repos, isEmpty);

      repos.seed([_repoA]);
      await env.container.read(repoPickerControllerProvider.notifier).refresh();

      final after =
          await env.container.read(repoPickerControllerProvider.future);
      expect((after as RepoPickerLoaded).repos, [_repoA]);
      expect(repos.tokensReceived, ['gho_test', 'gho_test'],
          reason: 'refresh should make a second call with the same token');
    });

    test('refresh recovers from a prior AuthError once the port stops '
        'throwing', () async {
      final repos = FakeGitHubReposPort(seededRepos: [_repoA])
        ..scriptError(const GitHubReposAuthError('401 first call'));
      final env = _buildContainer(repos: repos);
      await _primeAuthSignedIn(env.container);

      final first =
          await env.container.read(repoPickerControllerProvider.future);
      expect(first, isA<RepoPickerAuthError>());

      // scriptError is single-shot — second call returns the seeded list.
      await env.container.read(repoPickerControllerProvider.notifier).refresh();
      final second =
          await env.container.read(repoPickerControllerProvider.future);
      expect(second, isA<RepoPickerLoaded>());
      expect((second as RepoPickerLoaded).repos, [_repoA]);
    });
  });

  group('RepoPickerController.pick()', () {
    test(
        'successful pick persists lastOpenedRepo + lastOpenedWorkdir via '
        'SecureStoragePort and clears any stale lastOpenedJobId (NFR-2 '
        'cold-start preload)', () async {
      final repos = FakeGitHubReposPort(seededRepos: [_repoA]);
      final env = _buildContainer(repos: repos);
      // Seed a stale jobId so we can assert pick() clears it.
      await env.storage.writeString(
        SecureStorageKeys.lastOpenedJobId,
        'spec-stale-999',
      );
      await _primeAuthSignedIn(env.container);
      // Drive controller to Loaded.
      await env.container.read(repoPickerControllerProvider.future);

      await env.container
          .read(repoPickerControllerProvider.notifier)
          .pick(_repoA);

      // currentRepoProvider + currentWorkdirProvider are set.
      final expectedWorkdir =
          '${env.docsDir.path}/repos/${_repoA.owner}/${_repoA.name}';
      expect(
        env.container.read(currentRepoProvider),
        const RepoRef(
          owner: 'octocat',
          name: 'hello-world',
          defaultBranch: 'main',
        ),
      );
      expect(env.container.read(currentWorkdirProvider), expectedWorkdir);

      // lastOpenedRepo persisted with the codec's owner|name|branch shape.
      final repoBlob =
          await env.storage.readString(SecureStorageKeys.lastOpenedRepo);
      expect(repoBlob, isNotNull);
      expect(
        LastSessionRepoCodec.decode(repoBlob!),
        const RepoRef(
          owner: 'octocat',
          name: 'hello-world',
          defaultBranch: 'main',
        ),
      );
      // lastOpenedWorkdir matches the resolved workdir.
      expect(
        await env.storage.readString(SecureStorageKeys.lastOpenedWorkdir),
        expectedWorkdir,
      );
      // Stale jobId cleared — picking a new repo invalidates the
      // previously-open job.
      expect(
        await env.storage.containsKey(SecureStorageKeys.lastOpenedJobId),
        isFalse,
      );
      // Sanity: the fake git port observed a cloneOrOpen call.
      expect(env.git.cloned, isTrue);
    });
  });
}
