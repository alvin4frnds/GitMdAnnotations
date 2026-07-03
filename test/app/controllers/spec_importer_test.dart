import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/spec_importer.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/ports/clock_port.dart';

const _repo = RepoRef(owner: 'demo', name: 'payments-api');
const _identity = GitIdentity(name: 'Alice', email: 'alice@example.com');

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

SpecImporter _buildImporter(FakeFileSystem fs, FakeGitPort git, {DateTime? at}) {
  return SpecImporter(
    fs: fs,
    git: git,
    clock: _FixedClock(at ?? DateTime.utc(2026, 4, 21, 10, 30)),
  );
}

void main() {
  group('slugify', () {
    test('strips .md and lowercases', () {
      expect(slugify('My Notes.md'), 'spec-my-notes');
      expect(slugify('API_RATE_LIMIT.MD'), 'spec-api-rate-limit');
    });

    test('handles .markdown extension', () {
      expect(slugify('doc.markdown'), 'spec-doc');
      expect(slugify('DOC.MARKDOWN'), 'spec-doc');
    });

    test('strips .pdf extension', () {
      expect(slugify('Foo Bar.pdf'), 'spec-foo-bar');
      expect(slugify('DESIGN.PDF'), 'spec-design');
    });

    test('replaces non-alphanumerics with dashes and collapses runs', () {
      expect(slugify('foo--bar  baz.md'), 'spec-foo-bar-baz');
      expect(slugify('a.b.c.md'), 'spec-a-b-c');
    });

    test('empty / punctuation-only falls back to "imported"', () {
      expect(slugify('___.md'), 'spec-imported');
      expect(slugify('.md'), 'spec-imported');
    });

    test('strips unicode and trims leading/trailing dashes', () {
      expect(slugify('—draft—.md'), 'spec-draft');
    });
  });

  group('importFromRepoPath — success', () {
    test('reads source, composes provenance header, commits to claude-jobs',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/docs/feature.md', '# Feature\n\nBody.\n');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git,
          at: DateTime.utc(2026, 4, 21, 10, 30));

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/feature.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      final ok = outcome as SpecImportSuccess;
      expect(ok.job.jobId, 'spec-feature');
      expect(ok.commit.message, 'Import docs/feature.md as spec-feature');

      final tree = git.branches['claude-jobs']!;
      expect(tree.keys, ['jobs/pending/spec-feature/02-spec.md']);
      final written = tree.values.single;
      expect(
        written.split('\n').take(3).toList(),
        [
          '<!-- gitmdscribe:imported-from=docs/feature.md -->',
          '<!-- gitmdscribe:imported-at=2026-04-21T10:30:00.000Z -->',
          '',
        ],
      );
      // Original contents preserved verbatim after the header.
      expect(written.endsWith('# Feature\n\nBody.\n'), isTrue);
    });

    test('resolves collisions with -2, -3, …', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/docs/feature.md', '# x')
        ..seedFile('/repo/jobs/pending/spec-feature/02-spec.md', 'existing')
        ..seedFile(
            '/repo/jobs/pending/spec-feature-2/02-spec.md', 'also existing');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/feature.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      final ok = outcome as SpecImportSuccess;
      expect(ok.job.jobId, 'spec-feature-3');
      expect(
        git.branches['claude-jobs']!.keys,
        contains('jobs/pending/spec-feature-3/02-spec.md'),
      );
    });

    test('copies referenced inline images alongside the spec '
        '(spec-004 follow-up)', () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/docs/orchestrator/walk.md',
          '# Walk\n\n'
              '![A](assets/a.png)\n'
              '![B](assets/b.png)\n'
              '![Remote](https://example.com/c.png)\n'
              '![Title with spaces](assets/d.png "tooltip")\n',
        );
      await fs.writeBytes(
        '/repo/docs/orchestrator/assets/a.png',
        Uint8List.fromList([1, 1]),
      );
      await fs.writeBytes(
        '/repo/docs/orchestrator/assets/b.png',
        Uint8List.fromList([2, 2]),
      );
      await fs.writeBytes(
        '/repo/docs/orchestrator/assets/d.png',
        Uint8List.fromList([4, 4]),
      );
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/orchestrator/walk.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      // The spec lands as a string write…
      final stringTree = git.branches['claude-jobs']!;
      expect(
        stringTree.keys,
        contains('jobs/pending/spec-walk/02-spec.md'),
      );
      // …and the three local images land as binary writes alongside it,
      // at the same relative path the markdown references.
      final binTree = git.binaryBranches['claude-jobs']!;
      expect(binTree.keys.toSet(), {
        'jobs/pending/spec-walk/assets/a.png',
        'jobs/pending/spec-walk/assets/b.png',
        'jobs/pending/spec-walk/assets/d.png',
      });
      expect(binTree['jobs/pending/spec-walk/assets/a.png'], [1, 1]);
      expect(binTree['jobs/pending/spec-walk/assets/d.png'], [4, 4]);
    });

    test('skips image refs whose source file is missing — '
        'resolver shows loud error card at render time', () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/docs/walk.md',
          '# x\n![A](assets/exists.png)\n![B](assets/nope.png)\n',
        );
      await fs.writeBytes(
        '/repo/docs/assets/exists.png',
        Uint8List.fromList([1]),
      );
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/walk.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      final binTree = git.binaryBranches['claude-jobs']!;
      expect(binTree.keys, ['jobs/pending/spec-walk/assets/exists.png']);
    });

    test('image ref dedupe: the same href used twice is committed once',
        () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/walk.md',
          '![1](pic.png)\n\nlater: ![2](pic.png)\n',
        );
      await fs.writeBytes('/repo/pic.png', Uint8List.fromList([7]));
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'walk.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      final binTree = git.binaryBranches['claude-jobs']!;
      expect(binTree.keys, ['jobs/pending/spec-walk/pic.png']);
    });

    test('absolute / data: / file: refs are not copied', () async {
      final fs = FakeFileSystem()
        ..seedFile(
          '/repo/walk.md',
          '![A](/abs/x.png)\n'
              '![B](file:///etc/passwd)\n'
              '![C](data:image/png;base64,iVBOR)\n',
        );
      // Even if /abs/x.png exists in the fake FS, it must not be copied —
      // the resolver doesn't anchor absolute paths to the spec dir.
      await fs.writeBytes('/abs/x.png', Uint8List.fromList([9]));
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'walk.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      final binTree = git.binaryBranches['claude-jobs'] ?? const {};
      expect(binTree, isEmpty);
    });

    test('reservedJobIds forces a -n suffix even when disk is empty '
        '(AC-8 in-batch reservation)', () async {
      // Disk has no jobs/pending entries, so the disk probe alone would
      // hand back the bare slug. A prior file in the same batch already
      // claimed `spec-notes`, so the reservation must push this one to -2.
      final fs = FakeFileSystem()..seedFile('/repo/b/notes.md', '# x');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'b/notes.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
        reservedJobIds: const {'spec-notes'},
      );

      final ok = outcome as SpecImportSuccess;
      expect(ok.job.jobId, 'spec-notes-2');
      expect(
        git.branches['claude-jobs']!.keys,
        ['jobs/pending/spec-notes-2/02-spec.md'],
      );
    });

    test('reservedJobIds skips consecutive taken suffixes', () async {
      final fs = FakeFileSystem()..seedFile('/repo/c/notes.md', '# x');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'c/notes.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
        reservedJobIds: const {'spec-notes', 'spec-notes-2'},
      );

      expect((outcome as SpecImportSuccess).job.jobId, 'spec-notes-3');
    });

    test('leading-slash in relPath is normalised', () async {
      final fs = FakeFileSystem()..seedFile('/repo/notes.md', '# x');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: '/notes.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      expect(
        git.branches['claude-jobs']!.keys,
        ['jobs/pending/spec-notes/02-spec.md'],
      );
    });
  });

  group('importFromRepoPath — pdf', () {
    test('reads pdf bytes and commits spec.pdf to claude-jobs', () async {
      final pdfBytes = Uint8List.fromList(
        [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x00, 0x01, 0xFF],
      );
      final fs = FakeFileSystem();
      await fs.writeBytes('/repo/docs/hello.pdf', pdfBytes);
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/hello.pdf',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportSuccess>());
      final ok = outcome as SpecImportSuccess;
      expect(ok.job.jobId, 'spec-hello');
      expect(ok.commit.message, 'Import docs/hello.pdf as spec-hello');

      // PDFs land as raw bytes under binaryBranches; the string tree must
      // NOT also carry a spec.pdf entry (otherwise readers see two truths).
      final binTree = git.binaryBranches['claude-jobs']!;
      expect(binTree.keys, ['jobs/pending/spec-hello/spec.pdf']);
      expect(binTree.values.single, equals(pdfBytes));
      expect(
        git.branches['claude-jobs'] ?? const <String, String>{},
        isEmpty,
        reason: 'pdf import must not write any string-tree entries',
      );
    });

    test('resolves pdf-job collisions with -2, -3, …', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/jobs/pending/spec-hello/02-spec.md', 'existing md');
      await fs.writeBytes(
        '/repo/docs/hello.pdf',
        Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      );
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/hello.pdf',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      final ok = outcome as SpecImportSuccess;
      expect(ok.job.jobId, 'spec-hello-2');
      expect(
        git.binaryBranches['claude-jobs']!.keys,
        ['jobs/pending/spec-hello-2/spec.pdf'],
      );
    });
  });

  group('importFromRepoPath — failure', () {
    test('rejects paths already inside jobs/pending', () async {
      final fs = FakeFileSystem()
        ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', 'existing');
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'jobs/pending/spec-foo/02-spec.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportFailure>());
      expect(git.branches, isEmpty, reason: 'no commit on rejected import');
    });

    test('missing source file yields SpecImportFailure', () async {
      final fs = FakeFileSystem();
      final git = FakeGitPort();
      final importer = _buildImporter(fs, git);

      final outcome = await importer.importFromRepoPath(
        sourceRelPath: 'docs/missing.md',
        repo: _repo,
        workdir: '/repo',
        identity: _identity,
      );

      expect(outcome, isA<SpecImportFailure>());
      expect(git.branches, isEmpty);
    });
  });
}
