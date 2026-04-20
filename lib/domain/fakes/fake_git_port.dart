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

  final Map<String, List<Commit>> _log = {};
  final Map<String, Map<String, Map<String, String>>> _snapshots = {};
  final DateTime Function() _clock;

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
  }) async {
    final tree = branches.putIfAbsent(branch, () => <String, String>{});
    for (final f in files) {
      tree[f.path] = f.contents;
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
}

