import '../entities/github_repo.dart';
import '../ports/github_repos_port.dart';

/// In-memory [GitHubReposPort] for tests + dev-seed mockup flows.
///
/// Default behavior returns [seededRepos] for any non-empty token. Flip
/// [nextError] to exercise the UI's error path without needing a real
/// 401/network failure. Records calls via [tokensReceived] so tests can
/// assert the auth session's token was threaded through correctly.
class FakeGitHubReposPort implements GitHubReposPort {
  FakeGitHubReposPort({
    List<GitHubRepo> seededRepos = const [],
    Exception? nextError,
  })  : _repos = List<GitHubRepo>.of(seededRepos),
        _nextError = nextError;

  List<GitHubRepo> _repos;
  Exception? _nextError;

  /// Every token seen by [listUserRepos], in call order.
  final List<String> tokensReceived = [];

  void seed(List<GitHubRepo> repos) {
    _repos = List<GitHubRepo>.of(repos);
  }

  /// Arm the next call to [listUserRepos] to throw [err] instead of
  /// returning the seeded list. Consumed after one call; subsequent
  /// calls return the seeded list again.
  void scriptError(Exception err) {
    _nextError = err;
  }

  @override
  Future<List<GitHubRepo>> listUserRepos(String token) async {
    tokensReceived.add(token);
    final err = _nextError;
    if (err != null) {
      _nextError = null;
      throw err;
    }
    return List<GitHubRepo>.unmodifiable(_repos);
  }
}
