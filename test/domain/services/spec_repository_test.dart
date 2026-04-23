import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/job.dart';
import 'package:gitmdscribe/domain/entities/job_ref.dart';
import 'package:gitmdscribe/domain/entities/phase.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/entities/source_kind.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/services/spec_repository.dart';

void main() {
  const repo = RepoRef(owner: 'octocat', name: 'hello-world');
  const workdir = '/repo';

  SpecRepository build(FakeFileSystem fs) =>
      SpecRepository(fs: fs, workdir: workdir);

  group('SpecRepository.listOpenJobs', () {
    test(
        'lists jobs with resolved phases and source kinds, skipping invalid '
        'folders and folders without spec files', () async {
      final fs = FakeFileSystem()
        // spec-a: markdown, just 02-spec.md -> Phase.spec
        ..seedFile('$workdir/jobs/pending/spec-a/02-spec.md', '# a')
        // spec-b: markdown, has 04-spec-v2.md -> Phase.revised
        ..seedFile('$workdir/jobs/pending/spec-b/02-spec.md', '# b')
        ..seedFile('$workdir/jobs/pending/spec-b/03-review.md', '# r')
        ..seedFile('$workdir/jobs/pending/spec-b/04-spec-v2.md', '# v2')
        // spec-c: PDF source -> Phase.spec (only 02-spec.md absent, but
        // pdf + review exists). Phase resolver still wants 02-spec.md
        // or 05-approved; use a pdf job with just spec.pdf + 03-review.md.
        ..seedFile('$workdir/jobs/pending/spec-c/spec.pdf', '%PDF-1.4')
        ..seedFile('$workdir/jobs/pending/spec-c/03-review.md', '# r')
        // not-a-job: folder not matching JobRef pattern -> skipped
        ..seedFile('$workdir/jobs/pending/not-a-job/02-spec.md', '# nope')
        // spec-empty: matches JobRef pattern but has no spec content ->
        // skipped (Phase.resolve would throw)
        ..mkdirp('$workdir/jobs/pending/spec-empty');

      final jobs = await build(fs).listOpenJobs(repo);

      final byId = {for (final j in jobs) j.ref.jobId: j};
      expect(byId.keys.toSet(), {'spec-a', 'spec-b', 'spec-c'});
      expect(byId['spec-a']!.phase, Phase.spec);
      expect(byId['spec-a']!.sourceKind, SourceKind.markdown);
      expect(byId['spec-b']!.phase, Phase.revised);
      expect(byId['spec-b']!.sourceKind, SourceKind.markdown);
      expect(byId['spec-c']!.phase, Phase.review);
      expect(byId['spec-c']!.sourceKind, SourceKind.pdf);
      for (final j in jobs) {
        expect(j, isA<Job>());
        expect(j.ref.repo, repo);
      }
    });

    test('missing jobs/pending dir -> empty list', () async {
      final fs = FakeFileSystem();
      expect(await build(fs).listOpenJobs(repo), isEmpty);
    });
  });

  group('SpecRepository.loadSpec', () {
    JobRef refOf(String id) => JobRef(repo: repo, jobId: id);

    test('prefers highest-numbered 04-spec-v*.md (numeric, not lexical)',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$workdir/jobs/pending/spec-a/02-spec.md', 'v1')
        ..seedFile('$workdir/jobs/pending/spec-a/04-spec-v2.md', 'v2')
        ..seedFile('$workdir/jobs/pending/spec-a/04-spec-v3.md', 'v3')
        // v10 must beat v3 even though "10" < "3" lexically.
        ..seedFile('$workdir/jobs/pending/spec-a/04-spec-v10.md', 'v10');

      final file = await build(fs).loadSpec(refOf('spec-a'));
      expect(file.path, '$workdir/jobs/pending/spec-a/04-spec-v10.md');
      expect(file.contents, 'v10');
      expect(file.sourceKind, SourceKind.markdown);
    });

    test('falls back to 02-spec.md when no revisions exist', () async {
      final fs = FakeFileSystem()
        ..seedFile('$workdir/jobs/pending/spec-a/02-spec.md', 'orig');
      final file = await build(fs).loadSpec(refOf('spec-a'));
      expect(file.path, '$workdir/jobs/pending/spec-a/02-spec.md');
      expect(file.contents, 'orig');
      expect(file.sourceKind, SourceKind.markdown);
    });

    test(
        'returns base64-encoded contents for a PDF job and SourceKind.pdf',
        () async {
      final pdfBytes = <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34];
      final fs = FakeFileSystem()
        ..writeBytes('$workdir/jobs/pending/spec-p/spec.pdf', pdfBytes);

      final file = await build(fs).loadSpec(refOf('spec-p'));
      expect(file.sourceKind, SourceKind.pdf);
      expect(file.path, '$workdir/jobs/pending/spec-p/spec.pdf');
      expect(file.contents, base64.encode(pdfBytes));
    });

    test('throws SpecNotFound when no spec files exist', () async {
      final fs = FakeFileSystem()
        ..mkdirp('$workdir/jobs/pending/spec-none');
      await expectLater(
        build(fs).loadSpec(refOf('spec-none')),
        throwsA(isA<SpecNotFound>()
            .having((e) => e.job.jobId, 'job.jobId', 'spec-none')),
      );
    });

    test('sha is stable (same contents -> same hash), differs on change, '
        'and is 40 hex chars', () async {
      final fs = FakeFileSystem()
        ..seedFile('$workdir/jobs/pending/spec-a/02-spec.md', 'hello');
      final r = build(fs);

      final a = await r.loadSpec(JobRef(repo: repo, jobId: 'spec-a'));
      final b = await r.loadSpec(JobRef(repo: repo, jobId: 'spec-a'));
      expect(a.sha, b.sha);
      expect(a.sha, matches(RegExp(r'^[0-9a-f]{40}$')));

      await fs.writeString(
          '$workdir/jobs/pending/spec-a/02-spec.md', 'goodbye');
      final c = await r.loadSpec(JobRef(repo: repo, jobId: 'spec-a'));
      expect(c.sha, isNot(a.sha));
      expect(c.sha, matches(RegExp(r'^[0-9a-f]{40}$')));
    });
  });

  group('SpecRepository.readChangelog', () {
    JobRef refOf(String id) => JobRef(repo: repo, jobId: id);

    test('parses bottom-of-spec changelog in the latest .md', () async {
      const body = '# Spec\n\nBody.\n\n## Changelog\n\n'
          '- 2026-04-20 14:32 tablet: Clarified auth flow — TOTP required.\n'
          '- 2026-04-20 16:05 desktop: Revised to v2.\n';
      final fs = FakeFileSystem()
        ..seedFile('$workdir/jobs/pending/spec-a/02-spec.md', '# old')
        ..seedFile('$workdir/jobs/pending/spec-a/04-spec-v2.md', body);

      final entries = await build(fs).readChangelog(refOf('spec-a'));
      expect(entries, hasLength(2));
      expect(entries[0].author, 'tablet');
      expect(entries[1].author, 'desktop');
    });

    test('PDF job without sibling CHANGELOG.md -> empty list', () async {
      final fs = FakeFileSystem()
        ..writeBytes(
            '$workdir/jobs/pending/spec-p/spec.pdf', <int>[0x25, 0x50]);
      final entries = await build(fs).readChangelog(refOf('spec-p'));
      expect(entries, isEmpty);
    });

    test('PDF job WITH sibling CHANGELOG.md -> parsed entries', () async {
      final fs = FakeFileSystem()
        ..writeBytes(
            '$workdir/jobs/pending/spec-p/spec.pdf', <int>[0x25, 0x50])
        ..seedFile(
          '$workdir/jobs/pending/spec-p/CHANGELOG.md',
          '## Changelog\n\n'
              '- 2026-04-20 10:00 desktop: initial pdf upload\n',
        );
      final entries = await build(fs).readChangelog(refOf('spec-p'));
      expect(entries, hasLength(1));
      expect(entries.first.author, 'desktop');
    });
  });

  group('SpecNotFound', () {
    test('toString() includes the jobId', () {
      final ex = SpecNotFound(JobRef(repo: repo, jobId: 'spec-xyz'));
      expect(ex.toString(), 'SpecNotFound(spec-xyz)');
    });
  });
}
