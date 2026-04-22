import 'dart:typed_data';

import '../entities/changelog_entry.dart';
import '../entities/commit.dart';
import '../entities/git_identity.dart';
import '../entities/repo_ref.dart';
import '../ports/git_port.dart';
import '../services/changelog_parser.dart';

/// In-memory, scripted implementation of [GitPort] for domain tests.
/// Does zero real I/O. Tests seed state via [initial], script edge cases
/// through the public scripted* fields, and assert against the exposed
/// [branches], [backups], [fetchCount], and [cloned] state.
class FakeGitPort implements GitPort {
  FakeGitPort({
    Map<String, Map<String, String>>? initial,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        branches = _copy(initial);

  /// Branch name -> (path -> contents) working tree snapshot.
  final Map<String, Map<String, String>> branches;

  /// Branch name -> (path -> bytes) working tree snapshot for writes that
  /// specified raw [FileWrite.bytes]. Kept separate from [branches] so
  /// existing string-oriented assertions still work; tests that care about
  /// PNG round-trips read from this map directly.
  final Map<String, Map<String, Uint8List>> binaryBranches = {};

  final Map<String, List<Commit>> _log = {};
  final Map<String, Map<String, Map<String, String>>> _snapshots = {};
  final DateTime Function() _clock;

  /// Per-commit list of paths that were removed, keyed by commit SHA.
  /// Populated by [commit] whenever its `removals` list is non-empty so
  /// tests can assert "the right files were dropped in the right commit"
  /// without having to diff the branch snapshot.
  final Map<String, List<String>> _removalsBySha = {};

  /// Flipped true by [cloneOrOpen]; assertable by tests.
  bool cloned = false;

  /// Number of times [fetch] was invoked.
  int fetchCount = 0;

  /// One-shot script. If non-null, the next [mergeInto] call throws
  /// [GitMergeConflict] with these paths and clears the script.
  List<String>? scriptNextMergeConflict;

  /// Default outcome for [push]. Null -> returns `PushSuccess(headSha)`.
  PushOutcome? scriptedPushOutcome;

  /// Every [BackupRef] returned from [backupBranchHead], in call order.
  final List<BackupRef> backups = [];

  int _commitSeq = 0;

  static Map<String, Map<String, String>> _copy(
    Map<String, Map<String, String>>? src,
  ) {
    final out = <String, Map<String, String>>{};
    if (src == null) return out;
    src.forEach((branch, files) {
      out[branch] = Map<String, String>.from(files);
    });
    return out;
  }

  /// Commit chain for [branch], most recent first. Test-only helper.
  List<Commit> commitLog(String branch) =>
      List.unmodifiable(_log[branch] ?? const []);

  /// Paths recorded as `removals` on the commit with [sha], or an empty
  /// list when that commit was a pure write. Test-only helper.
  List<String> removalsOf(String sha) =>
      List.unmodifiable(_removalsBySha[sha] ?? const []);

  /// Capture the current working tree of [branch] under [sha] so that a
  /// later [resetHard] targeting that sha can restore it verbatim.
  void snapshotForRemote(String sha, {required String branch}) {
    _snapshots[branch] ??= {};
    _snapshots[branch]![sha] = Map<String, String>.from(
      branches[branch] ?? const <String, String>{},
    );
  }

  @override
  Future<void> cloneOrOpen(RepoRef repo, {required String workdir}) async {
    cloned = true;
  }

  @override
  Future<void> fetch(RepoRef repo, {required String branch}) async {
    fetchCount++;
  }

  @override
  Future<void> mergeInto(String sourceBranch,
      {required String target}) async {
    final scripted = scriptNextMergeConflict;
    if (scripted != null) {
      scriptNextMergeConflict = null;
      throw GitMergeConflict(List<String>.unmodifiable(scripted));
    }
    final source = branches[sourceBranch] ?? const <String, String>{};
    final dest = branches.putIfAbsent(target, () => <String, String>{});
    source.forEach((path, contents) {
      dest[path] = contents;
    });
  }

  @override
  Future<Commit> commit({
    required List<FileWrite> files,
    required String message,
    required GitIdentity id,
    required String branch,
    List<String> removals = const <String>[],
  }) async {
    final tree = branches.putIfAbsent(branch, () => <String, String>{});
    final binTree =
        binaryBranches.putIfAbsent(branch, () => <String, Uint8List>{});
    for (final f in files) {
      if (f.bytes != null) {
        binTree[f.path] = Uint8List.fromList(f.bytes!);
        // Drop any stale string-based entry at the same path so readers
        // don't see two truths.
        tree.remove(f.path);
      } else {
        tree[f.path] = f.contents;
        binTree.remove(f.path);
      }
    }
    for (final path in removals) {
      tree.remove(path);
      binTree.remove(path);
    }
    final existing = _log[branch] ?? <Commit>[];
    final parents = existing.isEmpty ? <String>[] : [existing.first.sha];
    final commit = Commit(
      sha: 'fake-commit-${++_commitSeq}',
      message: message,
      identity: id,
      timestamp: _clock(),
      parents: parents,
    );
    _log[branch] = [commit, ...existing];
    if (removals.isNotEmpty) {
      _removalsBySha[commit.sha] = List<String>.unmodifiable(removals);
    }
    return commit;
  }

  @override
  Future<PushOutcome> push(RepoRef repo, {required String branch}) async {
    final scripted = scriptedPushOutcome;
    if (scripted != null) return scripted;
    final head = await headSha(branch);
    return PushSuccess(head ?? 'fake-head-empty');
  }

  @override
  Future<void> resetHard(String ref) async {
    final (branch, snapshot) = _findSnapshot(ref);
    if (branch != null && snapshot != null) {
      branches[branch] = Map<String, String>.from(snapshot);
      final log = _log[branch] ?? <Commit>[];
      final idx = log.indexWhere((c) => c.sha == ref);
      if (idx >= 0) {
        _log[branch] = log.sublist(idx);
      }
      return;
    }
    // No scripted snapshot — drop the most recent commit on whichever
    // branch has the longest chain (the tests only keep one busy branch).
    final target = _mostRecentlyCommittedBranch();
    if (target == null) return;
    final log = _log[target]!;
    if (log.length <= 1) {
      _log[target] = [];
    } else {
      _log[target] = log.sublist(1);
    }
  }

  (String?, Map<String, String>?) _findSnapshot(String ref) {
    for (final entry in _snapshots.entries) {
      final snap = entry.value[ref];
      if (snap != null) return (entry.key, snap);
    }
    return (null, null);
  }

  String? _mostRecentlyCommittedBranch() {
    String? best;
    var bestLen = 0;
    _log.forEach((branch, log) {
      if (log.length > bestLen) {
        best = branch;
        bestLen = log.length;
      }
    });
    return best;
  }

  @override
  Future<BackupRef> backupBranchHead(
    String branch, {
    required String backupRoot,
  }) async {
    final at = _clock();
    final sha = await headSha(branch) ?? 'fake-head-empty';
    final stamp = at.toIso8601String().replaceAll(':', '-');
    final backup = BackupRef(
      path: '$backupRoot/$branch-$stamp/',
      commitSha: sha,
      createdAt: at,
    );
    backups.add(backup);
    return backup;
  }

  @override
  Future<List<ChangelogEntry>> readChangelog(String path) async {
    final contents = _lookupContents(path);
    if (contents == null) return const [];
    return parseChangelog(contents);
  }

  String? _lookupContents(String path) {
    for (final tree in branches.values) {
      final hit = tree[path];
      if (hit != null) return hit;
    }
    return null;
  }

  @override
  Future<List<String>> localBranches() async => List.unmodifiable(branches.keys);

  @override
  Future<String?> headSha(String branch) async {
    final log = _log[branch];
    if (log == null || log.isEmpty) return null;
    return log.first.sha;
  }

  @override
  Future<bool> bootstrapLocalBranchFromRemote({
    required String localBranch,
    required String remoteBranch,
  }) async {
    if (branches.containsKey(localBranch)) return true;
    // FakeGitPort doesn't track remote-only refs as a separate namespace
    // — branches is the ground truth. Callers that want the bootstrap
    // path exercised should seed the "remote" content under a branch
    // name that matches `remoteBranch` (or strip the `origin/` prefix).
    final key = remoteBranch.startsWith('origin/')
        ? remoteBranch.substring('origin/'.length)
        : remoteBranch;
    final tree = branches[key];
    if (tree == null) return false;
    branches[localBranch] = Map<String, String>.of(tree);
    final remoteLog = _log[key];
    if (remoteLog != null) _log[localBranch] = List.of(remoteLog);
    return true;
  }

  @override
  Future<int> countCommitsAhead({
    required String localBranch,
    required String remoteBranch,
  }) async {
    // Strip the `origin/` prefix so callers don't have to care about the
    // namespace — the fake has no remote-tracking concept, `branches` is
    // the ground truth.
    final remoteKey = remoteBranch.startsWith('origin/')
        ? remoteBranch.substring('origin/'.length)
        : remoteBranch;
    final localLog = _log[localBranch] ?? const <Commit>[];
    final remoteLog = _log[remoteKey] ?? const <Commit>[];
    if (localLog.isEmpty) return 0;
    final remoteShas = remoteLog.map((c) => c.sha).toSet();
    // Walk from the tip backwards; count commits until we hit one the
    // remote also has. The ordering convention in `_log` is newest-first
    // (see `commit()` above), so this mirrors the `git log` -> `rev-list`
    // semantics of "commits on local not in remote".
    var count = 0;
    for (final c in localLog) {
      if (remoteShas.contains(c.sha)) break;
      count++;
    }
    return count;
  }
}

