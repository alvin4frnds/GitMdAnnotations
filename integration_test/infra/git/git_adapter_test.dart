@Tags(['platform'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/ports/git_port.dart';
import 'package:gitmdannotations_tablet/infra/git/git_adapter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libgit2dart/libgit2dart.dart' as git2;

/// Integration tests for [GitAdapter] against a real libgit2 library.
///
/// These tests need a running Flutter host (device, emulator, or
/// integration_test harness) because the libgit2 Windows DLL is loaded via
/// the plugin's native side. They are tagged `platform` so the unit-test
/// suite (`flutter test test/`) skips them.
///
/// Local bare-repo workflow:
///   1. Create a "remote" bare repo under a temp dir.
///   2. Seed it with one commit on `main` containing a `README.md`, by
///      cloning/initialising a scratch clone and pushing back.
///   3. Point [GitAdapter] at a fresh workdir and exercise each port method.
///
/// The tests are deliberately coarse — the *unit* semantics of the adapter
/// (dispatch, credential seam, error mapping, push outcomes) are already
/// verified at the VM level in `test/infra/git/git_adapter_test.dart`. These
/// integration tests only need to prove that the libgit2 wiring actually
/// calls across to native code correctly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpRoot;
  late Directory originBare;
  late Directory workdir;
  late GitAdapter adapter;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('gitmd_adapter_it_');
    originBare = Directory('${tmpRoot.path}/origin.git')..createSync();
    workdir = Directory('${tmpRoot.path}/workdir')..createSync();
    Directory('${tmpRoot.path}/backups').createSync();

    // Seed the bare origin with one commit on `main` containing README.md.
    final seedRepo =
        git2.Repository.init(path: originBare.path, bare: true, initialHead: 'main');
    seedRepo.free();
    // Use a scratch workdir clone to push a seed commit.
    final scratch = Directory('${tmpRoot.path}/scratch')..createSync();
    final scratchRepo = git2.Repository.init(
      path: scratch.path,
      initialHead: 'main',
    );
    File('${scratch.path}/README.md').writeAsStringSync('# seed\n');
    final idx = scratchRepo.index;
    idx.add('README.md');
    idx.write();
    final sig = git2.Signature.create(name: 'Seed', email: 'seed@example.com');
    final tree = git2.Tree.lookup(repo: scratchRepo, oid: idx.writeTree());
    git2.Commit.create(
      repo: scratchRepo,
      updateRef: 'HEAD',
      author: sig,
      committer: sig,
      message: 'seed\n',
      tree: tree,
      parents: const [],
    );
    git2.Remote.create(
      repo: scratchRepo,
      name: 'origin',
      url: originBare.path,
    );
    final rem = git2.Remote.lookup(repo: scratchRepo, name: 'origin');
    rem.push(refspecs: const ['refs/heads/main:refs/heads/main']);
    scratchRepo.free();

    adapter = GitAdapter();
  });

  tearDown(() async {
    await adapter.dispose();
    if (await tmpRoot.exists()) {
      try {
        await tmpRoot.delete(recursive: true);
      } catch (_) {
        // Windows tmp locks are noisy; ignore.
      }
    }
  });

  test('cloneOrOpen clones into workdir', () async {
    final emptyWorkdir = Directory('${tmpRoot.path}/wd_clone')..createSync();
    await adapter.cloneOrOpen(
      RepoRef(owner: 'local', name: 'origin.git', defaultBranch: 'main'),
      workdir: emptyWorkdir.path,
    );
    // NOTE: the real `cloneOrOpen` derives the remote URL from the repo
    // owner/name. For this integration path we ignore the derived URL and
    // rely on a local `file://` override injected via `GitAdapter` config;
    // the concrete mechanism is TBD once real GitHub URLs are wired up in
    // T11 — this test documents the intended semantics.
    expect(File('${emptyWorkdir.path}/README.md').existsSync(), isTrue);
  }, skip: 'TODO: wire file:// URL override before enabling');

  test('commit writes atomic single commit', () async {
    // Bring workdir into an openable state first by cloning the bare origin
    // via libgit2 directly (the adapter\'s clone path doesn\'t yet know how
    // to talk to a file:// remote in tests).
    git2.Repository.clone(
      url: originBare.path,
      localPath: workdir.path,
      checkoutBranch: 'main',
    ).free();

    await adapter.cloneOrOpen(
      RepoRef(owner: 'local', name: 'origin.git', defaultBranch: 'main'),
      workdir: workdir.path,
    );

    final before = await adapter.headSha('main');
    final commit = await adapter.commit(
      files: const [
        FileWrite(path: 'jobs/pending/spec-x/03-review.md', contents: 'ok\n'),
      ],
      message: 'tablet: review',
      id: const GitIdentity(name: 'Tablet', email: 'tablet@example.com'),
      branch: 'main',
    );
    final after = await adapter.headSha('main');
    expect(commit.sha, isNot(equals(before)));
    expect(after, equals(commit.sha));
    expect(
      File('${workdir.path}/jobs/pending/spec-x/03-review.md')
          .readAsStringSync(),
      'ok\n',
    );
  }, skip: 'TODO: enable once cloneOrOpen file:// override ships');

  test('push to bare origin succeeds', () async {
    git2.Repository.clone(
      url: originBare.path,
      localPath: workdir.path,
      checkoutBranch: 'main',
    ).free();
    await adapter.cloneOrOpen(
      RepoRef(owner: 'local', name: 'origin.git', defaultBranch: 'main'),
      workdir: workdir.path,
    );
    await adapter.commit(
      files: const [FileWrite(path: 'a.txt', contents: 'a')],
      message: 'a',
      id: const GitIdentity(name: 'Tablet', email: 'tablet@example.com'),
      branch: 'main',
    );
    final outcome = await adapter.push(
      RepoRef(owner: 'local', name: 'origin.git', defaultBranch: 'main'),
      branch: 'main',
    );
    expect(outcome, isA<PushSuccess>());
  }, skip: 'TODO: enable once cloneOrOpen file:// override ships');

  test('push rejects non-fast-forward', () async {
    // Scenario: origin advances while the local work is stale. Attempting to
    // push should surface `PushRejectedNonFastForward` rather than throw.
  }, skip: 'TODO: scaffold remote-advance + stale-push helper');

  test('readChangelog parses ## Changelog section', () async {
    git2.Repository.clone(
      url: originBare.path,
      localPath: workdir.path,
      checkoutBranch: 'main',
    ).free();
    const md = '''
# Spec

## Changelog
- 2025-06-01 09:30 tablet: wrote notes
''';
    File('${workdir.path}/doc.md').writeAsStringSync(md);
    await adapter.cloneOrOpen(
      RepoRef(owner: 'local', name: 'origin.git', defaultBranch: 'main'),
      workdir: workdir.path,
    );
    final entries = await adapter.readChangelog('${workdir.path}/doc.md');
    expect(entries, hasLength(1));
    expect(entries.first.author, 'tablet');
  }, skip: 'TODO: enable once cloneOrOpen file:// override ships');
}
