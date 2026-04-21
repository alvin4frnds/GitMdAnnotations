/// Summary of a GitHub repository the authenticated user has access to,
/// as returned by `GET /user/repos`. Drives the RepoPicker UI — which
/// repo the user selects becomes the `RepoRef` the app operates against.
///
/// Deliberately narrower than the full GitHub API payload: we only keep
/// fields the picker + downstream clone flow need. Extend if a future
/// feature wants description / topics / etc.
class GitHubRepo {
  const GitHubRepo({
    required this.owner,
    required this.name,
    required this.defaultBranch,
    required this.isPrivate,
  });

  /// `owner.login` in the API payload — the namespace (user or org).
  final String owner;

  /// `name` in the API payload — the short repo name (not `full_name`).
  final String name;

  /// `default_branch` — typically `main`. Used by `GitAdapter.cloneOrOpen`.
  final String defaultBranch;

  /// Whether the repo is private. Surfaced in the picker so the user can
  /// distinguish at a glance; otherwise not load-bearing.
  final bool isPrivate;

  String get fullName => '$owner/$name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitHubRepo &&
          other.owner == owner &&
          other.name == name &&
          other.defaultBranch == defaultBranch &&
          other.isPrivate == isPrivate;

  @override
  int get hashCode => Object.hash(owner, name, defaultBranch, isPrivate);

  @override
  String toString() => 'GitHubRepo($fullName, default: $defaultBranch)';
}
