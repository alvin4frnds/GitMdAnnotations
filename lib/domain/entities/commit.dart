import 'git_identity.dart';

/// A git commit returned by `GitPort.commit` (IMPLEMENTATION.md §4.2).
///
/// [parents] is the ordered parent-SHA list; a merge commit has multiple
/// parents, a root commit has zero.
class Commit {
  const Commit({
    required this.sha,
    required this.message,
    required this.identity,
    required this.timestamp,
    required this.parents,
  });

  final String sha;
  final String message;
  final GitIdentity identity;
  final DateTime timestamp;
  final List<String> parents;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Commit) return false;
    if (other.sha != sha) return false;
    if (other.message != message) return false;
    if (other.identity != identity) return false;
    if (other.timestamp != timestamp) return false;
    if (other.parents.length != parents.length) return false;
    for (var i = 0; i < parents.length; i++) {
      if (other.parents[i] != parents[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(sha, message, identity, timestamp, Object.hashAll(parents));

  @override
  String toString() =>
      'Commit(sha: $sha, message: $message, identity: $identity, parents: $parents)';
}
