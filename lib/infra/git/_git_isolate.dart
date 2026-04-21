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
    final repo = git2.Repository.open(workdir);
    _repos[workdir] = repo;
    return repo;
  }

  void register(String workdir, git2.Repository repo) {
    _repos[workdir] = repo;
  }

  bool isTracked(String workdir) => _repos.containsKey(workdir);

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
  state.register(req.workdir, repo);
  return GitResponseOk<void>(id: req.id, value: null);
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
  final sourceRef = git2.Reference.lookup(
    repo: repo,
    name: 'refs/heads/${req.sourceBranch}',
  );
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
  final oid = git2.Oid.fromSHA(repo: repo, sha: req.ref);
  repo.reset(oid: oid, resetType: git2.GitReset.hard);
  return GitResponseOk<void>(id: req.id, value: null);
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
