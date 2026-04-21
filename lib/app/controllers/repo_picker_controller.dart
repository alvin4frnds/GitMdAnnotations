import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/github_repo.dart';
import '../../domain/entities/repo_ref.dart';
import '../../domain/ports/github_repos_port.dart';
import '../last_session.dart';
import '../providers/auth_providers.dart';
import '../providers/repo_picker_providers.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';
import 'auth_controller.dart';

/// Test seam for the app's documents directory. Production uses
/// `path_provider` which throws `MissingPluginException` under
/// `fvm flutter test` on the host VM — the test override swaps in a
/// temp directory so `pick()` can run end-to-end in unit tests.
///
/// Kept as a provider (rather than a ctor arg on the notifier) so the
/// existing `AsyncNotifierProvider.new` factory in
/// `repo_picker_providers.dart` doesn't have to grow a new parameter.
final docsDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

/// UI-facing state for the RepoPicker screen. See the three concrete
/// subclasses — the picker sits between sign-in and job-list in the
/// `_AuthGate` router.
sealed class RepoPickerState {
  const RepoPickerState();
}

/// Inflight load or reload. UI shows a spinner.
class RepoPickerLoading extends RepoPickerState {
  const RepoPickerLoading();
}

/// Terminal-pre-pick: list is loaded. Empty lists land here too — the
/// UI renders a "no repos visible to this token" empty state.
class RepoPickerLoaded extends RepoPickerState {
  const RepoPickerLoaded(this.repos);
  final List<GitHubRepo> repos;
}

/// Auth token was rejected by GitHub. UI should prompt sign-out + re-auth.
class RepoPickerAuthError extends RepoPickerState {
  const RepoPickerAuthError(this.message);
  final String message;
}

/// DNS / timeout / mid-transfer drop. UI should offer "retry".
class RepoPickerNetworkError extends RepoPickerState {
  const RepoPickerNetworkError(this.message);
  final String message;
}

/// Mid-pick: clone-or-open is in flight. UI disables interactions and
/// shows the picked repo name.
class RepoPickerOpening extends RepoPickerState {
  const RepoPickerOpening(this.repo);
  final GitHubRepo repo;
}

/// Clone-or-open on the picked repo failed (auth, network, on-device
/// filesystem quirks, corrupt existing workdir). UI surfaces [message]
/// to the user and re-enables interactions so a different repo can be
/// picked. [previousRepos] preserves the loaded list so the UI doesn't
/// bounce back to the spinner.
class RepoPickerCloneFailed extends RepoPickerState {
  const RepoPickerCloneFailed({
    required this.repo,
    required this.message,
    required this.previousRepos,
  });
  final GitHubRepo repo;
  final String message;
  final List<GitHubRepo> previousRepos;
}

/// AsyncNotifier that loads the signed-in user's repos on first build
/// and handles pick / retry intents.
///
/// On `pick(repo)` the controller:
///   1. clones or opens `<appDocsDir>/repos/<owner>/<name>` via
///      [gitPortProvider], passing the auth token so private repos work,
///   2. sets [currentWorkdirProvider] + [currentRepoProvider],
///   3. lands back in a Loaded-but-selected state — navigation flip
///      happens in the UI gate (`_AuthGate` watches `currentRepoProvider`).
class RepoPickerController extends AsyncNotifier<RepoPickerState> {
  GitHubReposPort get _repos => ref.read(gitHubReposPortProvider);

  @override
  Future<RepoPickerState> build() async {
    return _load();
  }

  Future<RepoPickerState> _load() async {
    final auth = ref.read(authControllerProvider).value;
    if (auth is! AuthSignedIn) {
      return const RepoPickerAuthError('not signed in');
    }
    try {
      final list = await _repos.listUserRepos(auth.session.token);
      return RepoPickerLoaded(list);
    } on GitHubReposAuthError catch (e) {
      return RepoPickerAuthError(e.message);
    } on GitHubReposNetworkError catch (e) {
      return RepoPickerNetworkError(e.message);
    }
  }

  /// Re-runs the list fetch. Called by the "Retry" action in the error
  /// states and by the pull-to-refresh gesture on the loaded list.
  Future<void> refresh() async {
    state = const AsyncValue.data(RepoPickerLoading());
    state = await AsyncValue.guard(_load);
  }

  /// User selected [repo]. Clones (or re-opens) the local workdir and
  /// sets the "current" providers. Idempotent — picking the same repo
  /// twice just re-opens the existing workdir.
  Future<void> pick(GitHubRepo repo) async {
    final auth = ref.read(authControllerProvider).value;
    if (auth is! AuthSignedIn) {
      state = const AsyncValue.data(
        RepoPickerAuthError('not signed in'),
      );
      return;
    }
    // Snapshot the currently-loaded list so we can restore it on clone
    // failure — otherwise the UI would fall back to showing an empty
    // picker and the user loses the list they already saw.
    final previous = state.value;
    final previousRepos = previous is RepoPickerLoaded
        ? previous.repos
        : const <GitHubRepo>[];
    state = AsyncValue.data(RepoPickerOpening(repo));
    final docs = await ref.read(docsDirectoryProvider)();
    final workdir = '${docs.path}/repos/${repo.owner}/${repo.name}';
    final repoRef = RepoRef(
      owner: repo.owner,
      name: repo.name,
      defaultBranch: repo.defaultBranch,
    );
    try {
      await ref.read(gitPortProvider).cloneOrOpen(
            repoRef,
            workdir: workdir,
          );
    } catch (e) {
      // Clone failed. Surface a real error state (not AsyncValue.error —
      // that gets swallowed in the UI because `hasValue` stays true on
      // the previous Opening frame). Keep the repo list visible so the
      // user can try a different one without bouncing back to loading.
      state = AsyncValue.data(RepoPickerCloneFailed(
        repo: repo,
        message: e.toString(),
        previousRepos: previousRepos,
      ));
      return;
    }
    ref.read(currentWorkdirProvider.notifier).state = workdir;
    ref.read(currentRepoProvider.notifier).state = repoRef;
    // NFR-2 cold-start preload: persist the picked repo+workdir via
    // SecureStoragePort so the next cold launch skips RepoPicker and
    // lands directly on JobList. Clear any stale `lastOpenedJobId` —
    // picking a new repo invalidates whatever job the user was
    // previously viewing.
    final storage = ref.read(secureStorageProvider);
    await saveLastOpenedRepo(storage, repo: repoRef, workdir: workdir);
    await saveLastOpenedJobId(storage, null);
    // First-open auto-sync: a fresh clone has no local `claude-jobs`
    // branch yet, which means JobList would render empty until the user
    // manually hits Sync Down. Kick off a sync in the background so the
    // list populates on its own — JobList already listens for
    // `SyncDone` and invalidates itself. Cold-start restores (re-opening
    // an existing workdir) skip this because `claude-jobs` is already
    // present locally.
    //
    // The `localBranches()` gate is awaited here (rather than inside a
    // separate unawaited helper) so that `syncDown()` is invoked before
    // the state flip below. `SyncController.syncDown` flips its state
    // to `SyncInProgress` synchronously on the first line of its body,
    // so by the time the UI gate swaps in JobList on the next frame the
    // "Sync Down" button already reads "Syncing…" — no one-frame flash
    // of the idle label.
    final hasLocalJobs = (await ref.read(gitPortProvider).localBranches())
        .contains('claude-jobs');
    if (!hasLocalJobs) {
      unawaited(ref
          .read(syncControllerProvider.notifier)
          .syncDown(repo: repoRef, workdir: workdir));
    }
    // Re-emit the loaded list so the UI can render "picked <name>"
    // feedback before the gate flips to JobList.
    state = AsyncValue.data(RepoPickerLoaded(
      previousRepos.isNotEmpty
          ? previousRepos
          : await _repos.listUserRepos(auth.session.token),
    ));
  }
}
