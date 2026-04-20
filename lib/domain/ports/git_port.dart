import '../entities/changelog_entry.dart';
import '../entities/commit.dart';
import '../entities/git_identity.dart';
import '../entities/repo_ref.dart';

/// Abstract boundary between the `git` domain and libgit2 / the filesystem.
///
/// The real implementation (T10) is `GitAdapter` running in a dedicated
/// isolate; domain tests use `FakeGitPort`. See IMPLEMENTATION.md §4.2 and
/// TabletApp-PRD.md §5.2, §5.7–5.9, §9.
abstract class GitPort {
  /// Clone if missing; otherwise open the existing working tree at [workdir].
  Future<void> cloneOrOpen(RepoRef repo, {required String workdir});

  /// `git fetch origin`, limited to the given [branch].
  Future<void> fetch(RepoRef repo, {required String branch});

  /// Fast-forward [target] to [sourceBranch] in the local working copy.
  /// Throws [GitMergeConflict] if a non-trivial merge is required.
  Future<void> mergeInto(String sourceBranch, {required String target});

  /// Atomic commit: writes every [files] entry and creates exactly one
  /// commit with [message] authored by [id] on [branch].
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
  });

  /// Push [branch] to origin. Returns a typed outcome (success or typed
  /// rejection). Never throws for non-fast-forward; throws only on
  /// unrecoverable errors (e.g. network down, bad auth at the transport
  /// layer).
  Future<PushOutcome> push(RepoRef repo, {required String branch});

  /// Hard-reset HEAD to [ref] on the current branch.
  Future<void> resetHard(String ref);

  /// Copy the working tree at the current HEAD of [branch] to a new
  /// timestamped directory under [backupRoot] and return a handle.
  Future<BackupRef> backupBranchHead(
    String branch, {
    required String backupRoot,
  });

  /// Parse a `## Changelog` section out of the markdown at [path]
  /// (relative to the workdir) OR the sibling `CHANGELOG.md`. Returns
  /// entries in file order (oldest first). Missing file or missing
  /// section returns an empty list. Malformed entries throw
  /// [FormatException].
  Future<List<ChangelogEntry>> readChangelog(String path);

  /// Local branches currently present. Smoke-test helper for tests.
  Future<List<String>> localBranches();

  /// Current HEAD sha of [branch]. `null` if the branch does not exist
  /// locally.
  Future<String?> headSha(String branch);
}

/// A single file write that will be staged + committed as part of
/// [GitPort.commit]. [path] is relative to the repo workdir.
class FileWrite {
  const FileWrite({required this.path, required this.contents});

  final String path;
  final String contents;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileWrite && other.path == path && other.contents == contents;

  @override
  int get hashCode => Object.hash(path, contents);

  @override
  String toString() => 'FileWrite(path: $path)';
}

/// Sealed root of every outcome [GitPort.push] can report without
/// throwing. Non-fast-forward and auth rejections are expected control
/// flow (they drive the conflict / re-auth UI); transport-level errors
/// still throw.
sealed class PushOutcome {
  const PushOutcome();
}

class PushSuccess extends PushOutcome {
  const PushSuccess(this.sha);
  final String sha;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushSuccess && other.sha == sha;

  @override
  int get hashCode => sha.hashCode;

  @override
  String toString() => 'PushSuccess($sha)';
}

class PushRejectedNonFastForward extends PushOutcome {
  const PushRejectedNonFastForward({
    required this.remoteSha,
    required this.localSha,
  });

  final String remoteSha;
  final String localSha;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushRejectedNonFastForward &&
          other.remoteSha == remoteSha &&
          other.localSha == localSha;

  @override
  int get hashCode => Object.hash(remoteSha, localSha);

  @override
  String toString() =>
      'PushRejectedNonFastForward(remote: $remoteSha, local: $localSha)';
}

class PushRejectedAuth extends PushOutcome {
  const PushRejectedAuth();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushRejectedAuth;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'PushRejectedAuth';
}

/// Handle to an on-device backup created before a remote-wins reset.
class BackupRef {
  const BackupRef({
    required this.path,
    required this.commitSha,
    required this.createdAt,
  });

  final String path;
  final String commitSha;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupRef &&
          other.path == path &&
          other.commitSha == commitSha &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(path, commitSha, createdAt);

  @override
  String toString() =>
      'BackupRef(path: $path, sha: $commitSha, at: $createdAt)';
}

/// Sealed root of every error [GitPort] is allowed to throw. Callers
/// pattern-match on concrete subtypes; we never leak raw libgit2 errors.
sealed class GitError implements Exception {
  const GitError();
}

class GitMergeConflict extends GitError {
  const GitMergeConflict(this.conflictedPaths);
  final List<String> conflictedPaths;

  @override
  String toString() => 'GitMergeConflict(paths: $conflictedPaths)';
}

class GitDirtyWorkingTree extends GitError {
  const GitDirtyWorkingTree();
  @override
  String toString() => 'GitDirtyWorkingTree';
}

class GitCorrupted extends GitError {
  const GitCorrupted(this.details);
  final String details;
  @override
  String toString() => 'GitCorrupted($details)';
}

class GitNetworkFailure extends GitError {
  const GitNetworkFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'GitNetworkFailure(cause: $cause)';
}
