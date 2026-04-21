import 'dart:io';
import 'dart:isolate';

import 'package:libgit2dart/libgit2dart.dart' as git2;

import '../../domain/entities/changelog_entry.dart';
import '../../domain/entities/commit.dart' as dom;
import '../../domain/entities/git_identity.dart';
import '../../domain/ports/git_port.dart';
import '../../domain/services/changelog_parser.dart';
import '_git_isolate_helpers.dart';
import '_git_messages.dart';

/// Entry point for the long-lived background isolate that owns every
/// libgit2 handle for this process. The UI side boots the isolate via
/// [Isolate.spawn], hands in its `ReceivePort.sendPort`, then awaits the
/// echo of the isolate's own `SendPort` before dispatching any request.
///
/// The isolate keeps one open [git2.Repository] cached by workdir path —
/// repeated `cloneOrOpen` / `commit` / `push` calls for the same repo
/// share the handle instead of re-opening from disk on each request.
///
/// All libgit2 calls are synchronous FFI; exceptions are captured and
/// surfaced as [GitResponseError], never leaked as isolate unhandled
/// errors.
void gitIsolateEntry(SendPort uiSendPort) {
  final receive = ReceivePort();
  uiSendPort.send(receive.sendPort);

  final state = _IsolateState();

  receive.listen((message) {
    if (message is GitReqShutdown) {
      state.closeAll();
      receive.close();
      return;
    }
    if (message is! GitRequest) return;
    _dispatch(state, message).then((resp) => uiSendPort.send(resp));
  });
}

class _IsolateState {
  final Map<String, git2.Repository> _repos = {};

  git2.Repository openOrReuse(String workdir) {
    final cached = _repos[workdir];
    if (cached != null) return cached;
    // Phase 1 is explicitly single-repo: close any previous entries so
    // `_onlyRepo` doesn't trip when the user switches repos at runtime.
    _closeOthers(workdir);
    final repo = git2.Repository.open(workdir);
    _repos[workdir] = repo;
    return repo;
  }

  void register(String workdir, git2.Repository repo) {
    _closeOthers(workdir);
    _repos[workdir] = repo;
  }

  bool isTracked(String workdir) => _repos.containsKey(workdir);

  /// Frees and drops every tracked repo whose workdir isn't [keep]. Used
  /// by the register/open paths so switching repos at runtime doesn't
  /// accumulate `state._repos` entries — Phase 1's `_onlyRepo` guard
  /// requires exactly one tracked repo.
  void _closeOthers(String keep) {
    final stale = _repos.keys.where((k) => k != keep).toList();
    for (final w in stale) {
      try {
        _repos[w]?.free();
      } catch (_) {}
      _repos.remove(w);
    }
  }

  void closeAll() {
    for (final repo in _repos.values) {
      try {
        repo.free();
      } catch (_) {}
    }
    _repos.clear();
  }
}

Future<GitResponse> _dispatch(_IsolateState state, GitRequest req) async {
  try {
    return switch (req) {
      GitReqCloneOrOpen() => _handleCloneOrOpen(state, req),
      GitReqFetch() => _handleFetch(state, req),
      GitReqMerge() => _handleMerge(state, req),
      GitReqCommit() => _handleCommit(state, req),
      GitReqPush() => _handlePush(state, req),
      GitReqResetHard() => _handleResetHard(state, req),
      GitReqBackup() => await _handleBackup(state, req),
      GitReqReadChangelog() => await _handleReadChangelog(state, req),
      GitReqLocalBranches() => _handleLocalBranches(state, req),
      GitReqHeadSha() => _handleHeadSha(state, req),
      GitReqBootstrapLocalBranch() => _handleBootstrapLocalBranch(state, req),
      GitReqCommitsAhead() => _handleCommitsAhead(state, req),
    };
  } catch (e) {
    return GitResponseError(id: req.id, error: e);
  }
}

GitResponse _handleCloneOrOpen(_IsolateState state, GitReqCloneOrOpen req) {
  final dir = Directory(req.workdir);
  final alreadyRepo = Directory('${req.workdir}/.git').existsSync();
  if (alreadyRepo) {
    state.openOrReuse(req.workdir);
    return GitResponseOk<void>(id: req.id, value: null);
  }
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final isEmpty = dir.listSync(followLinks: false).isEmpty;
  if (!isEmpty) {
    throw GitCorrupted(
      'cloneOrOpen: ${req.workdir} is non-empty but is not a git repo',
    );
  }
  final url = req.remoteUrlOverride ??
      'https://github.com/${req.owner}/${req.name}.git';
  final callbacks = buildCallbacks(req.token);
  final repo = git2.Repository.clone(
    url: url,
    localPath: req.workdir,
    checkoutBranch: req.defaultBranch,
    callbacks: callbacks,
  );
  _bootstrapLocalSidecarBranch(repo);
  state.register(req.workdir, repo);
  return GitResponseOk<void>(id: req.id, value: null);
}

/// After a fresh clone, ensure `refs/heads/claude-jobs` exists locally
/// whenever the origin has a `claude-jobs` branch. Fixes the
/// `Issues.md` High: `Repository.clone` only creates `refs/heads/<default>`
/// plus remote-tracking refs, so the first `adapter.commit(...,
/// branch: 'claude-jobs')` then fails inside `checkoutBranch` because the
/// local sidecar branch doesn't exist — only `refs/remotes/origin/claude-jobs`
/// does. `integration_test/sync_conflict_test.dart` previously worked
/// around this with a direct libgit2 call before invoking the adapter;
/// that workaround becomes unnecessary once this lands.
///
/// No-op when the origin has no `claude-jobs` branch (the create-from-main
/// path is `SyncService.syncDown`'s responsibility — see the separate
/// "claude-jobs bootstrap from origin/main" entry in Issues.md).
void _bootstrapLocalSidecarBranch(git2.Repository repo) {
  const sidecar = 'claude-jobs';
  // Is there already a local claude-jobs? If yes, nothing to do.
  try {
    git2.Branch.lookup(repo: repo, name: sidecar);
    return;
  } on git2.LibGit2Error {
    // Fall through — not found is the expected case after clone.
  }
  // Find the remote-tracking branch.
  final git2.Branch remote;
  try {
    remote = git2.Branch.lookup(
      repo: repo,
      name: 'origin/$sidecar',
      type: git2.GitBranch.remote,
    );
  } on git2.LibGit2Error {
    // Origin has no sidecar branch yet — create-from-main is handled elsewhere.
    return;
  }
  final targetOid = remote.target;
  final targetCommit = git2.Commit.lookup(repo: repo, oid: targetOid);
  final local = git2.Branch.create(
    repo: repo,
    name: sidecar,
    target: targetCommit,
  );
  // Track `origin/<sidecar>` so push refspec matching + future NFF
  // detection see this as a real tracking branch rather than a
  // fresh-branch push.
  local.setUpstream('origin/$sidecar');
}

GitResponse _handleFetch(_IsolateState state, GitReqFetch req) {
  final repo = state.openOrReuse(_workdirFromName(state, req.owner, req.name));
  final remote = git2.Remote.lookup(repo: repo, name: 'origin');
  remote.fetch(
    refspecs: ['refs/heads/${req.branch}:refs/remotes/origin/${req.branch}'],
    callbacks: buildCallbacks(req.token),
  );
  return GitResponseOk<void>(id: req.id, value: null);
}

GitResponse _handleMerge(_IsolateState state, GitReqMerge req) {
  final repo = _onlyRepo(state);
  checkoutBranch(repo, req.target);
  final sourceRef = _lookupLocalOrRemoteRef(repo, req.sourceBranch);
  final analysis = git2.Merge.analysis(repo: repo, theirHead: sourceRef.target);
  final result = analysis.result;
  if (result.contains(git2.GitMergeAnalysis.upToDate)) {
    return GitResponseOk<void>(id: req.id, value: null);
  }
  if (result.contains(git2.GitMergeAnalysis.fastForward) ||
      result.contains(git2.GitMergeAnalysis.unborn)) {
    git2.Reference.setTarget(
      repo: repo,
      name: 'refs/heads/${req.target}',
      target: sourceRef.target,
    );
    git2.Checkout.head(repo: repo, strategy: const {git2.GitCheckout.force});
    return GitResponseOk<void>(id: req.id, value: null);
  }
  final annotated =
      git2.AnnotatedCommit.lookup(repo: repo, oid: sourceRef.target);
  git2.Merge.commit(repo: repo, commit: annotated);
  if (repo.index.hasConflicts) {
    final paths = repo.index.conflicts.keys.toList();
    repo.stateCleanup();
    throw GitMergeConflict(paths);
  }
  // No conflicts — the caller is expected to seal with a commit via
  // commit(). Leave MERGE_HEAD in place so CommitPlanner can produce a
  // merge commit.
  return GitResponseOk<void>(id: req.id, value: null);
}

GitResponse _handleCommit(_IsolateState state, GitReqCommit req) {
  final repo = _onlyRepo(state);
  checkoutBranch(repo, req.branch);
  final workdir = repo.workdir;
  for (final f in req.files) {
    final target = File('$workdir${f.path}');
    final parent = target.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    final bytes = f.bytes;
    if (bytes != null) {
      target.writeAsBytesSync(bytes);
    } else {
      target.writeAsStringSync(f.contents);
    }
  }
  final index = repo.index;
  index.addAll(req.files.map((f) => f.path).toList());
  index.write();
  final treeOid = index.writeTree();
  final tree = git2.Tree.lookup(repo: repo, oid: treeOid);
  final sig = git2.Signature.create(
    name: req.authorName,
    email: req.authorEmail,
  );
  final headRef = git2.Reference.lookup(
    repo: repo,
    name: 'refs/heads/${req.branch}',
  );
  final parentOid = headRef.target;
  final parents = <git2.Commit>[git2.Commit.lookup(repo: repo, oid: parentOid)];
  final oid = git2.Commit.create(
    repo: repo,
    updateRef: 'refs/heads/${req.branch}',
    author: sig,
    committer: sig,
    message: req.message,
    tree: tree,
    parents: parents,
  );
  final created = git2.Commit.lookup(repo: repo, oid: oid);
  final commit = dom.Commit(
    sha: oid.sha,
    message: req.message,
    identity: GitIdentity(name: req.authorName, email: req.authorEmail),
    timestamp: DateTime.fromMillisecondsSinceEpoch(created.time * 1000),
    parents: created.parents.map((p) => p.sha).toList(growable: false),
  );
  return GitResponseOk<dom.Commit>(id: req.id, value: commit);
}

GitResponse _handlePush(_IsolateState state, GitReqPush req) {
  final repo = _onlyRepo(state);
  final remote = git2.Remote.lookup(repo: repo, name: 'origin');
  final localRef = git2.Reference.lookup(
    repo: repo,
    name: 'refs/heads/${req.branch}',
  );
  final localSha = localRef.target.sha;
  try {
    remote.push(
      refspecs: ['refs/heads/${req.branch}:refs/heads/${req.branch}'],
      callbacks: buildCallbacks(req.token),
    );
  } catch (e) {
    final outcome = mapPushError(e, remote: remote, localSha: localSha);
    if (outcome != null) {
      return GitResponseOk<PushOutcome>(id: req.id, value: outcome);
    }
    rethrow;
  }
  return GitResponseOk<PushOutcome>(
    id: req.id,
    value: PushSuccess(localSha),
  );
}

GitResponse _handleResetHard(_IsolateState state, GitReqResetHard req) {
  final repo = _onlyRepo(state);
  final oid = _resolveRefToOid(repo, req.ref);
  repo.reset(oid: oid, resetType: git2.GitReset.hard);
  return GitResponseOk<void>(id: req.id, value: null);
}

/// Hex-SHA fast path, RevParse fallback for anything else (branch refs
/// like `'origin/claude-jobs'`, tag names, `'HEAD~3'`, etc.).
///
/// Fixes the `Issues.md` High where callers like
/// `ConflictResolver.archiveAndReset` pass `'origin/claude-jobs'` but
/// `git2.Oid.fromSHA` validates against a hex regex and throws
/// `ArgumentError` for non-hex input. Historical behavior preserved for
/// the hex path so existing SHA-based callers (integration tests, future
/// direct-SHA resets) are unchanged.
git2.Oid _resolveRefToOid(git2.Repository repo, String ref) {
  if (_hexSha.hasMatch(ref)) {
    return git2.Oid.fromSHA(repo: repo, sha: ref);
  }
  final obj = git2.RevParse.single(repo: repo, spec: ref);
  if (obj is git2.Commit) return obj.oid;
  if (obj is git2.Tag) return obj.targetOid;
  throw ArgumentError.value(
    ref,
    'ref',
    'resolved to ${obj.runtimeType}, not a commit or tag',
  );
}

final _hexSha = RegExp(r'^[0-9a-fA-F]{7,40}$');

/// Resolves [name] to a [git2.Reference], trying `refs/heads/<name>`
/// first (local branch) and then `refs/remotes/<name>` (remote-tracking).
/// Lets the merge/sync code pass either `'main'` (local) or
/// `'origin/main'` (remote-tracking) without caring about the namespace.
git2.Reference _lookupLocalOrRemoteRef(git2.Repository repo, String name) {
  try {
    return git2.Reference.lookup(repo: repo, name: 'refs/heads/$name');
  } on git2.LibGit2Error {
    // Fall through — not a local branch, try remote-tracking.
  }
  return git2.Reference.lookup(repo: repo, name: 'refs/remotes/$name');
}

Future<GitResponse> _handleBackup(
  _IsolateState state,
  GitReqBackup req,
) async {
  final repo = _onlyRepo(state);
  checkoutBranch(repo, req.branch);
  final sha = git2.Reference.lookup(
    repo: repo,
    name: 'refs/heads/${req.branch}',
  ).target.sha;
  final now = DateTime.now();
  final stamp = now.toIso8601String().replaceAll(':', '-');
  final destPath = '${req.backupRoot}/${req.branch}-$stamp';
  final source = Directory(repo.workdir);
  final dest = Directory(destPath);
  await copyDirectory(source, dest, skipDotGit: true);
  return GitResponseOk<BackupRef>(
    id: req.id,
    value: BackupRef(path: destPath, commitSha: sha, createdAt: now),
  );
}

Future<GitResponse> _handleReadChangelog(
  _IsolateState state,
  GitReqReadChangelog req,
) async {
  final file = File(req.path);
  if (!file.existsSync()) {
    return GitResponseOk<List<ChangelogEntry>>(id: req.id, value: const []);
  }
  final contents = await file.readAsString();
  final entries = parseChangelog(contents);
  return GitResponseOk<List<ChangelogEntry>>(id: req.id, value: entries);
}

GitResponse _handleLocalBranches(
  _IsolateState state,
  GitReqLocalBranches req,
) {
  final repo = _onlyRepo(state);
  final branches = git2.Branch.list(repo: repo, type: git2.GitBranch.local);
  final names = branches.map((b) => b.name).toList(growable: false);
  return GitResponseOk<List<String>>(id: req.id, value: names);
}

GitResponse _handleHeadSha(_IsolateState state, GitReqHeadSha req) {
  final repo = _onlyRepo(state);
  try {
    final ref = git2.Reference.lookup(
      repo: repo,
      name: 'refs/heads/${req.branch}',
    );
    return GitResponseOk<String?>(id: req.id, value: ref.target.sha);
  } catch (_) {
    return GitResponseOk<String?>(id: req.id, value: null);
  }
}

/// Create `refs/heads/<localBranch>` pointing at `refs/remotes/<remoteBranch>`'s
/// current tip, with upstream tracking set. No-op (returns `false`) when
/// the remote branch doesn't exist locally — callers (Sync Down) then
/// know to fall back to "nothing to merge". Idempotent: returns `true`
/// when the local branch already existed.
///
/// Mirrors the clone-time bootstrap in `_bootstrapLocalSidecarBranch`;
/// extracted here so Sync Down can bootstrap a sidecar the origin
/// acquired *after* RepoPicker ran (common case: user pushes
/// `claude-jobs` to an existing repo, then opens the app).
GitResponse _handleBootstrapLocalBranch(
  _IsolateState state,
  GitReqBootstrapLocalBranch req,
) {
  final repo = _onlyRepo(state);
  // Already exists locally → idempotent success.
  try {
    git2.Branch.lookup(repo: repo, name: req.localBranch);
    return GitResponseOk<bool>(id: req.id, value: true);
  } on git2.LibGit2Error {
    // Not found — fall through to create from remote.
  }
  final git2.Branch remote;
  try {
    remote = git2.Branch.lookup(
      repo: repo,
      name: req.remoteBranch,
      type: git2.GitBranch.remote,
    );
  } on git2.LibGit2Error {
    // Origin doesn't have this branch either — nothing to bootstrap.
    return GitResponseOk<bool>(id: req.id, value: false);
  }
  final commit = git2.Commit.lookup(repo: repo, oid: remote.target);
  final local = git2.Branch.create(
    repo: repo,
    name: req.localBranch,
    target: commit,
  );
  local.setUpstream(req.remoteBranch);
  return GitResponseOk<bool>(id: req.id, value: true);
}

/// Count of commits [localBranch] is ahead of [remoteBranch]. Returns 0
/// when either branch can't be resolved (fresh clone pre-fetch, sidecar
/// not yet materialised, etc.) — the caller feeds this into the JobList
/// "Sync Up [N]" badge, so silently returning 0 keeps the UI honest
/// without crashing on a perfectly normal setup transition.
GitResponse _handleCommitsAhead(
  _IsolateState state,
  GitReqCommitsAhead req,
) {
  final repo = _onlyRepo(state);
  final localOid = _tryResolveBranchOid(repo, req.localBranch);
  final remoteOid = _tryResolveBranchOid(repo, req.remoteBranch);
  if (localOid == null || remoteOid == null) {
    return GitResponseOk<int>(id: req.id, value: 0);
  }
  if (localOid.sha == remoteOid.sha) {
    return GitResponseOk<int>(id: req.id, value: 0);
  }
  try {
    final counts = repo.aheadBehind(local: localOid, upstream: remoteOid);
    // aheadBehind → [ahead, behind].
    return GitResponseOk<int>(id: req.id, value: counts.first);
  } on git2.LibGit2Error {
    return GitResponseOk<int>(id: req.id, value: 0);
  }
}

/// Resolves a local-or-remote branch name to its tip Oid. Tries
/// `refs/heads/<name>` first, then `refs/remotes/<name>`. Returns null
/// when neither exists.
git2.Oid? _tryResolveBranchOid(git2.Repository repo, String name) {
  try {
    final ref = git2.Reference.lookup(repo: repo, name: 'refs/heads/$name');
    return ref.target;
  } on git2.LibGit2Error {
    // Fall through.
  }
  try {
    final ref = git2.Reference.lookup(repo: repo, name: 'refs/remotes/$name');
    return ref.target;
  } on git2.LibGit2Error {
    return null;
  }
}

/// Returns the single tracked repository in [state], or throws if zero /
/// multiple are tracked. The adapter in Phase 1 only works with one repo
/// at a time, so this guard catches logic errors early.
git2.Repository _onlyRepo(_IsolateState state) {
  if (state._repos.length == 1) return state._repos.values.first;
  if (state._repos.isEmpty) {
    throw StateError('GitAdapter: no repository open — call cloneOrOpen first');
  }
  throw StateError(
    'GitAdapter: multiple repositories open — not supported in Phase 1',
  );
}

String _workdirFromName(_IsolateState state, String owner, String name) {
  // Phase 1: there is always exactly one tracked repo; ignore owner/name
  // and return its workdir. When multi-repo support lands, this helper
  // grows into a real lookup keyed by RepoRef.
  return state._repos.keys.first;
}
