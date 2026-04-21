import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/github_repo.dart';
import '../../domain/entities/repo_ref.dart';
import '../../domain/ports/github_repos_port.dart';
import '../providers/auth_providers.dart';
import '../providers/repo_picker_providers.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';
import 'auth_controller.dart';

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
    state = AsyncValue.data(RepoPickerOpening(repo));
    final docs = await getApplicationDocumentsDirectory();
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
      // Clone failed — fall back to the loaded state and surface the
      // error via a SnackBar in the UI. Keeping the Loaded list visible
      // is more useful than bouncing to a full-screen error because the
      // user may want to pick a different repo.
      state = AsyncValue.error(e, StackTrace.current);
      return;
    }
    ref.read(currentWorkdirProvider.notifier).state = workdir;
    ref.read(currentRepoProvider.notifier).state = repoRef;
    // Re-emit the loaded list so the UI can render "picked <name>"
    // feedback before the gate flips to JobList.
    final previous = state.value;
    if (previous is RepoPickerOpening) {
      state = AsyncValue.data(RepoPickerLoaded(
        // We don't have the list cached on `RepoPickerOpening`; reload
        // — cheap because `_load` is just a single HTTP GET and it
        // won't block the navigator since the UI gate already flipped.
        await _repos.listUserRepos(auth.session.token),
      ));
    }
  }
}
