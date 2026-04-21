import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../domain/entities/changelog_entry.dart';
import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/entities/repo_ref.dart';
import '../../domain/ports/git_port.dart';
import '_git_isolate.dart';
import '_git_messages.dart';

/// Loader that returns the current GitHub OAuth/PAT token, or `null` if the
/// user is signed out. The adapter calls this on every remote-touching
/// method (clone, fetch, push) because plugins like `flutter_secure_storage`
/// cannot be reached from inside an isolate — the credential must be
/// fetched on the UI isolate and marshalled across.
typedef CredentialsLoader = Future<String?> Function();

/// Production [GitPort] adapter backed by libgit2dart.
///
/// libgit2 calls are synchronous FFI and would stall the UI isolate during
/// a sync (IMPLEMENTATION.md §2.4), so every request is dispatched to a
/// dedicated long-lived background isolate. The isolate is spawned lazily
/// on the first call so that [GitAdapter()] stays cheap at app start.
///
/// The [CredentialsLoader] seam is intentional: the [GitPort] contract
/// doesn't know about tokens (T10 spec note). We resolve the token on the
/// UI side right before every remote operation and piggyback it on the
/// request payload. That keeps the domain layer — including [GitPort] and
/// every fake — unaware of authentication plumbing.
class GitAdapter implements GitPort {
  GitAdapter({CredentialsLoader? credentialsLoader})
      : _credentialsLoader = credentialsLoader ?? _noCredentials,
        _remoteUrlOverride = null;

  /// Test-only constructor that pins every subsequent [cloneOrOpen] to
  /// [remoteUrlOverride] instead of the production
  /// `https://github.com/<owner>/<name>.git` URL. Used by
  /// `integration_test/sync_conflict_test.dart` and other integration
  /// tests that need a local bare-repo fixture reached via `file://`.
  ///
  /// The override is intentionally constructor-scoped (not method-scoped)
  /// so the [GitPort] interface stays production-only — no test concern
  /// leaks into the domain contract.
  @visibleForTesting
  GitAdapter.withRemoteUrlOverride({
    required String remoteUrlOverride,
    CredentialsLoader? credentialsLoader,
  })  : _credentialsLoader = credentialsLoader ?? _noCredentials,
        _remoteUrlOverride = remoteUrlOverride;

  static Future<String?> _noCredentials() async => null;

  final CredentialsLoader _credentialsLoader;
  final String? _remoteUrlOverride;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<void>? _readyCompleter;

  final Map<int, Completer<GitResponse>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;

  Future<SendPort> _ensureIsolate() async {
    if (_sendPort != null) return _sendPort!;
    if (_readyCompleter != null) {
      await _readyCompleter!.future;
      return _sendPort!;
    }
    final ready = _readyCompleter = Completer<void>();
    final receive = _receivePort = ReceivePort();
    receive.listen(_onIsolateMessage);
    _isolate = await Isolate.spawn<SendPort>(
      gitIsolateEntry,
      receive.sendPort,
      debugName: 'git-adapter',
    );
    await ready.future;
    return _sendPort!;
  }

  void _onIsolateMessage(Object? message) {
    if (message is SendPort) {
      _sendPort = message;
      _readyCompleter?.complete();
      return;
    }
    if (message is GitResponse) {
      final completer = _pending.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
    }
  }

  Future<GitResponse> _send(GitRequest Function(int id) build) async {
    if (_disposed) {
      throw StateError('GitAdapter has been disposed');
    }
    final port = await _ensureIsolate();
    final id = _nextId++;
    final completer = Completer<GitResponse>();
    _pending[id] = completer;
    port.send(build(id));
    return completer.future;
  }

  T _unwrap<T>(GitResponse resp) {
    if (resp is GitResponseError) {
      final err = resp.error;
      if (err is Exception) throw err;
      if (err is Error) throw err;
      throw StateError('GitAdapter isolate error: $err');
    }
    if (resp is GitResponseOk<T>) return resp.value;
    if (resp is GitResponseOk) return resp.value as T;
    throw StateError('Unexpected response type ${resp.runtimeType}');
  }

  @override
  Future<void> cloneOrOpen(RepoRef repo, {required String workdir}) async {
    final token = await _credentialsLoader();
    final resp = await _send(
      (id) => GitReqCloneOrOpen(
        id: id,
        owner: repo.owner,
        name: repo.name,
        defaultBranch: repo.defaultBranch,
        workdir: workdir,
        token: token,
        remoteUrlOverride: _remoteUrlOverride,
      ),
    );
    _unwrap<void>(resp);
  }

  @override
  Future<void> fetch(RepoRef repo, {required String branch}) async {
    final token = await _credentialsLoader();
    final resp = await _send(
      (id) => GitReqFetch(
        id: id,
        owner: repo.owner,
        name: repo.name,
        branch: branch,
        token: token,
      ),
    );
    _unwrap<void>(resp);
  }

  @override
  Future<void> mergeInto(String sourceBranch, {required String target}) async {
    final resp = await _send(
      (id) => GitReqMerge(id: id, sourceBranch: sourceBranch, target: target),
    );
    _unwrap<void>(resp);
  }

  @override
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
  }) async {
    final resp = await _send(
      (reqId) => GitReqCommit(
        id: reqId,
        files: files
            .map((f) => SerializedFileWrite(
                  path: f.path,
                  contents: f.contents,
                  bytes: f.bytes,
                ))
            .toList(),
        message: message,
        authorName: id.name,
        authorEmail: id.email,
        branch: branch,
      ),
    );
    return _unwrap<Commit>(resp);
  }

  @override
  Future<PushOutcome> push(RepoRef repo, {required String branch}) async {
    final token = await _credentialsLoader();
    final resp = await _send(
      (id) => GitReqPush(
        id: id,
        owner: repo.owner,
        name: repo.name,
        branch: branch,
        token: token,
      ),
    );
    return _unwrap<PushOutcome>(resp);
  }

  @override
  Future<void> resetHard(String ref) async {
    final resp = await _send((id) => GitReqResetHard(id: id, ref: ref));
    _unwrap<void>(resp);
  }

  @override
  Future<BackupRef> backupBranchHead(
    String branch, {
    required String backupRoot,
  }) async {
    final resp = await _send(
      (id) => GitReqBackup(id: id, branch: branch, backupRoot: backupRoot),
    );
    return _unwrap<BackupRef>(resp);
  }

  @override
  Future<List<ChangelogEntry>> readChangelog(String path) async {
    final resp = await _send((id) => GitReqReadChangelog(id: id, path: path));
    return _unwrap<List<ChangelogEntry>>(resp);
  }

  @override
  Future<List<String>> localBranches() async {
    final resp = await _send((id) => GitReqLocalBranches(id: id));
    return _unwrap<List<String>>(resp);
  }

  @override
  Future<String?> headSha(String branch) async {
    final resp = await _send((id) => GitReqHeadSha(id: id, branch: branch));
    // Cast through dynamic because a nullable String erases at runtime.
    if (resp is GitResponseOk) return resp.value as String?;
    _unwrap<String?>(resp);
    return null;
  }

  @override
  Future<bool> bootstrapLocalBranchFromRemote({
    required String localBranch,
    required String remoteBranch,
  }) async {
    final resp = await _send((id) => GitReqBootstrapLocalBranch(
          id: id,
          localBranch: localBranch,
          remoteBranch: remoteBranch,
        ));
    return _unwrap<bool>(resp);
  }

  /// Shuts the background isolate down. Safe to call multiple times; later
  /// calls become no-ops.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final port = _sendPort;
    final isolate = _isolate;
    final receive = _receivePort;

    if (port != null) {
      try {
        port.send(const GitReqShutdown());
      } catch (_) {
        // Isolate may already be dead.
      }
    }
    // Drop pending awaits.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('GitAdapter disposed'));
      }
    }
    _pending.clear();
    isolate?.kill(priority: Isolate.beforeNextEvent);
    receive?.close();
    _sendPort = null;
    _isolate = null;
    _receivePort = null;
  }
}
