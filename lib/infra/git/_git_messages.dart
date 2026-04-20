/// IPC message types exchanged between [GitAdapter] and the background git
/// isolate. Kept separate so both the UI-side dispatcher and the isolate
/// body can import them without dragging in libgit2 FFI at the UI side.
library;

/// Serialized form of `FileWrite` — the domain value object is hostile to
/// `SendPort.send` because its class lives outside `dart:core`. Plain
/// string fields cross isolate boundaries without ceremony.
class SerializedFileWrite {
  const SerializedFileWrite({required this.path, required this.contents});
  final String path;
  final String contents;
}

/// Sealed root of every request. Every subclass carries the monotonically
/// increasing request [id] used to route the paired [GitResponse] back.
sealed class GitRequest {
  const GitRequest({required this.id});
  final int id;
}

class GitReqCloneOrOpen extends GitRequest {
  const GitReqCloneOrOpen({
    required super.id,
    required this.owner,
    required this.name,
    required this.defaultBranch,
    required this.workdir,
    required this.token,
  });
  final String owner;
  final String name;
  final String defaultBranch;
  final String workdir;
  final String? token;
}

class GitReqFetch extends GitRequest {
  const GitReqFetch({
    required super.id,
    required this.owner,
    required this.name,
    required this.branch,
    required this.token,
  });
  final String owner;
  final String name;
  final String branch;
  final String? token;
}

class GitReqMerge extends GitRequest {
  const GitReqMerge({
    required super.id,
    required this.sourceBranch,
    required this.target,
  });
  final String sourceBranch;
  final String target;
}

class GitReqCommit extends GitRequest {
  const GitReqCommit({
    required super.id,
    required this.files,
    required this.message,
    required this.authorName,
    required this.authorEmail,
    required this.branch,
  });
  final List<SerializedFileWrite> files;
  final String message;
  final String authorName;
  final String authorEmail;
  final String branch;
}

class GitReqPush extends GitRequest {
  const GitReqPush({
    required super.id,
    required this.owner,
    required this.name,
    required this.branch,
    required this.token,
  });
  final String owner;
  final String name;
  final String branch;
  final String? token;
}

class GitReqResetHard extends GitRequest {
  const GitReqResetHard({required super.id, required this.ref});
  final String ref;
}

class GitReqBackup extends GitRequest {
  const GitReqBackup({
    required super.id,
    required this.branch,
    required this.backupRoot,
  });
  final String branch;
  final String backupRoot;
}

class GitReqReadChangelog extends GitRequest {
  const GitReqReadChangelog({required super.id, required this.path});
  final String path;
}

class GitReqLocalBranches extends GitRequest {
  const GitReqLocalBranches({required super.id});
}

class GitReqHeadSha extends GitRequest {
  const GitReqHeadSha({required super.id, required this.branch});
  final String branch;
}

/// Lifecycle-only message — carries no request id because no reply is
/// expected. The isolate self-terminates on receipt.
class GitReqShutdown {
  const GitReqShutdown();
}

/// Sealed root of every response. Always echoes the triggering request's
/// [id] so the dispatcher can complete the right [Completer].
sealed class GitResponse {
  const GitResponse({required this.id});
  final int id;
}

/// Success case. [value] is typed at the use site; when the method is
/// `Future<void>` the isolate sends `null`.
class GitResponseOk<T> extends GitResponse {
  const GitResponseOk({required super.id, required this.value});
  final T value;
}

/// Failure case. [error] is a domain [GitError] or another exception that
/// the dispatcher rethrows on the UI side.
class GitResponseError extends GitResponse {
  const GitResponseError({required super.id, required this.error});
  final Object error;
}
