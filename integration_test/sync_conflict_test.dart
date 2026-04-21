@Tags(['platform'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/ports/git_port.dart';
import 'package:gitmdannotations_tablet/domain/services/sync_service.dart';
import 'package:gitmdannotations_tablet/infra/git/git_adapter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libgit2dart/libgit2dart.dart' as git2;

/// End-to-end integration tests for `SyncService.syncUp` against a real
/// libgit2 bare-repo fixture. Covers IMPLEMENTATION.md §4.6 + FR-1.32
/// "remote-wins": a divergent local `claude-jobs` is archived on-device
/// and reset to `origin/claude-jobs`, then `origin/main` is merged on top.
///
/// `GitAdapter.withRemoteUrlOverride` points the adapter at a `file://`
/// bare repo. Tagged `platform` — only runs on device via
/// `flutter test integration_test/sync_conflict_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const repo = RepoRef(
    owner: 'local',
    name: 'origin.git',
    defaultBranch: 'main',
  );
  const identity = GitIdentity(name: 'Tablet', email: 'tablet@example.com');

  late Directory tmpRoot;
  late Directory originBare;
  late Directory workdir;
  late String backupRoot;
  late String remoteUrl;
  late GitAdapter adapter;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('gitmd_sync_it_');
    originBare = Directory('${tmpRoot.path}/origin.git')..createSync();
    workdir = Directory('${tmpRoot.path}/workdir')..createSync();
    backupRoot = '${tmpRoot.path}/backups';
    Directory(backupRoot).createSync();
    // Uri.file produces `file:///C:/...` on Windows (triple-slash form
    // libgit2 expects) and `file:///path` on POSIX.
    remoteUrl = Uri.file(originBare.path).toString();
    _seedOrigin(originBare, tmpRoot);
    adapter = GitAdapter.withRemoteUrlOverride(remoteUrlOverride: remoteUrl);
  });

  tearDown(() async {
    await adapter.dispose();
    if (await tmpRoot.exists()) {
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {
        // Windows temp locks are noisy; ignore.
      }
    }
  });

  test('syncUp happy path on claude-jobs pushes and emits Complete', () async {
    _bootstrapWorkdirWithJobsBranch(workdir, remoteUrl);
    await adapter.cloneOrOpen(repo, workdir: workdir.path);
    await adapter.commit(
      files: const [FileWrite(path: 'note.md', contents: 'local\n')],
      message: 'local note',
      id: identity,
      branch: 'claude-jobs',
    );

    final service = SyncService(git: adapter);
    final events = await service
        .syncUp(repo, workdir: workdir.path, backupRoot: backupRoot)
        .toList();

    expect(
      events.map((e) => e.runtimeType.toString()).toList(),
      ['SyncStarted', 'SyncPushing', 'SyncComplete'],
    );
  });

  test('syncUp on diverged claude-jobs archives local + resets to remote',
      () async {
    _bootstrapWorkdirWithJobsBranch(workdir, remoteUrl);
    await adapter.cloneOrOpen(repo, workdir: workdir.path);
    await adapter.commit(
      files: const [FileWrite(path: 'local-a.md', contents: 'a\n')],
      message: 'local a',
      id: identity,
      branch: 'claude-jobs',
    );
    await adapter.commit(
      files: const [FileWrite(path: 'local-b.md', contents: 'b\n')],
      message: 'local b',
      id: identity,
      branch: 'claude-jobs',
    );
    _advanceOriginJobs(originBare, tmpRoot);

    final service = SyncService(git: adapter);
    final events = await service
        .syncUp(repo, workdir: workdir.path, backupRoot: backupRoot)
        .toList();

    final archived = events.whereType<SyncConflictArchived>().single;
    final archivePath = archived.backup.path;
    expect(
      events.map((e) => e.runtimeType.toString()).toList(),
      ['SyncStarted', 'SyncPushing', 'SyncConflictArchived', 'SyncComplete'],
    );
    expect(Directory(archivePath).existsSync(), isTrue);
    expect(File('$archivePath/local-a.md').existsSync(), isTrue);
    expect(File('$archivePath/local-b.md').existsSync(), isTrue);
    expect(File('${workdir.path}/remote-added.md').existsSync(), isTrue);
  });
}

/// Stages [file] at [path] in [repo]'s index, writes a single commit
/// on top of [updateRef]'s current tip, and returns the new Oid.
git2.Oid _writeCommit(
  git2.Repository repo, {
  required String path,
  required String contents,
  required String message,
  required String updateRef,
  required List<git2.Commit> parents,
}) {
  File('${repo.workdir}$path').writeAsStringSync(contents);
  final idx = repo.index;
  idx.add(path);
  idx.write();
  final sig = git2.Signature.create(name: 'Bot', email: 'bot@example.com');
  final tree = git2.Tree.lookup(repo: repo, oid: idx.writeTree());
  return git2.Commit.create(
    repo: repo,
    updateRef: updateRef,
    author: sig,
    committer: sig,
    message: message,
    tree: tree,
    parents: parents,
  );
}

/// Seeds [originBare] with `main` + a `claude-jobs` branch at the same
/// commit, via a scratch repo.
void _seedOrigin(Directory originBare, Directory tmpRoot) {
  git2.Repository.init(
    path: originBare.path,
    bare: true,
    initialHead: 'main',
  ).free();
  final scratch = Directory('${tmpRoot.path}/scratch_seed')..createSync();
  final repo = git2.Repository.init(path: scratch.path, initialHead: 'main');
  final oid = _writeCommit(
    repo,
    path: 'README.md',
    contents: '# seed\n',
    message: 'seed\n',
    updateRef: 'HEAD',
    parents: const [],
  );
  git2.Branch.create(
    repo: repo,
    name: 'claude-jobs',
    target: git2.Commit.lookup(repo: repo, oid: oid),
  );
  git2.Remote.create(repo: repo, name: 'origin', url: originBare.path);
  git2.Remote.lookup(repo: repo, name: 'origin').push(refspecs: const [
    'refs/heads/main:refs/heads/main',
    'refs/heads/claude-jobs:refs/heads/claude-jobs',
  ]);
  repo.free();
}

/// Clones [remoteUrl] into [workdir] and creates a local
/// `refs/heads/claude-jobs`. Real `cloneOrOpen` checks out only `main`;
/// the M1c `claude-jobs` bootstrap path is still deferred.
void _bootstrapWorkdirWithJobsBranch(Directory workdir, String remoteUrl) {
  final repo = git2.Repository.clone(
    url: remoteUrl,
    localPath: workdir.path,
    checkoutBranch: 'main',
  );
  final remoteJobs = git2.Reference.lookup(
    repo: repo,
    name: 'refs/remotes/origin/claude-jobs',
  );
  git2.Branch.create(
    repo: repo,
    name: 'claude-jobs',
    target: git2.Commit.lookup(repo: repo, oid: remoteJobs.target),
  );
  repo.free();
}

/// Advances `refs/heads/claude-jobs` on [originBare] by one commit —
/// simulates a parallel push from another device.
void _advanceOriginJobs(Directory originBare, Directory tmpRoot) {
  final scratch = Directory('${tmpRoot.path}/scratch_remote_advance')
    ..createSync();
  final repo = git2.Repository.clone(
    url: originBare.path,
    localPath: scratch.path,
    checkoutBranch: 'claude-jobs',
  );
  final head = git2.Reference.lookup(
    repo: repo,
    name: 'refs/heads/claude-jobs',
  );
  _writeCommit(
    repo,
    path: 'remote-added.md',
    contents: 'remote\n',
    message: 'remote advance\n',
    updateRef: 'refs/heads/claude-jobs',
    parents: [git2.Commit.lookup(repo: repo, oid: head.target)],
  );
  git2.Remote.lookup(repo: repo, name: 'origin').push(refspecs: const [
    'refs/heads/claude-jobs:refs/heads/claude-jobs',
  ]);
  repo.free();
}
