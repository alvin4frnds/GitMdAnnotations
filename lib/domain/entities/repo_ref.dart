/// A reference to a GitHub repository the tablet operates on.
///
/// See IMPLEMENTATION.md §2.6 (ubiquitous language). `defaultBranch` is the
/// upstream default branch (e.g. `main`); the tablet writes only to the
/// `claude-jobs` sidecar branch, never here.
class RepoRef {
  const RepoRef({
    required this.owner,
    required this.name,
    this.defaultBranch = 'main',
  });

  final String owner;
  final String name;
  final String defaultBranch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoRef &&
          other.owner == owner &&
          other.name == name &&
          other.defaultBranch == defaultBranch;

  @override
  int get hashCode => Object.hash(owner, name, defaultBranch);

  @override
  String toString() =>
      'RepoRef(owner: $owner, name: $name, defaultBranch: $defaultBranch)';
}
