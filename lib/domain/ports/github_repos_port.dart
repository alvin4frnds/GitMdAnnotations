import '../entities/github_repo.dart';

/// Boundary between the `repo-picker` feature and the outside world
/// (the GitHub REST API). The real implementation lives in
/// `lib/infra/github/dio_github_repos_adapter.dart`; tests use
/// `FakeGitHubReposPort`.
///
/// Intentionally minimal — the picker only needs to list the signed-in
/// user's repos. Search / pagination UX are future M1d concerns.
abstract class GitHubReposPort {
  /// Lists every repo the authenticated [token] holder can access.
  ///
  /// Throws [GitHubReposAuthError] on 401/403 (token expired or lacks
  /// `repo` scope) and [GitHubReposNetworkError] on transport failure.
  Future<List<GitHubRepo>> listUserRepos(String token);
}

/// Bearer token rejected or missing required scopes. UI should prompt
/// for re-auth.
class GitHubReposAuthError implements Exception {
  const GitHubReposAuthError(this.message);
  final String message;
  @override
  String toString() => 'GitHubReposAuthError($message)';
}

/// DNS / timeout / mid-transfer drop. UI should surface "offline —
/// retry" rather than "permission denied".
class GitHubReposNetworkError implements Exception {
  const GitHubReposNetworkError(this.message);
  final String message;
  @override
  String toString() => 'GitHubReposNetworkError($message)';
}
