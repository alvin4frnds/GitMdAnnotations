import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/job.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/phase.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/source_kind.dart';

void main() {
  const repo = RepoRef(owner: 'o', name: 'n');

  group('Job', () {
    test('constructs with ref, phase, sourceKind', () {
      final ref = JobRef(repo: repo, jobId: 'spec-a');
      final job = Job(
        ref: ref,
        phase: Phase.review,
        sourceKind: SourceKind.markdown,
      );
      expect(job.ref, ref);
      expect(job.phase, Phase.review);
      expect(job.sourceKind, SourceKind.markdown);
    });

    test('equal fields produce equal instances', () {
      final ref = JobRef(repo: repo, jobId: 'spec-a');
      final a = Job(
        ref: ref,
        phase: Phase.spec,
        sourceKind: SourceKind.pdf,
      );
      final b = Job(
        ref: ref,
        phase: Phase.spec,
        sourceKind: SourceKind.pdf,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different phase makes jobs unequal', () {
      final ref = JobRef(repo: repo, jobId: 'spec-a');
      final a = Job(
        ref: ref,
        phase: Phase.spec,
        sourceKind: SourceKind.markdown,
      );
      final b = Job(
        ref: ref,
        phase: Phase.approved,
        sourceKind: SourceKind.markdown,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes jobId and phase', () {
      final ref = JobRef(repo: repo, jobId: 'spec-xyz');
      final job = Job(
        ref: ref,
        phase: Phase.review,
        sourceKind: SourceKind.markdown,
      );
      final s = job.toString();
      expect(s, contains('spec-xyz'));
      expect(s, contains('review'));
    });
  });

  group('SourceKind', () {
    test('has markdown and pdf values', () {
      expect(SourceKind.values, [SourceKind.markdown, SourceKind.pdf]);
    });
  });
}
