import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';

void main() {
  const repo = RepoRef(owner: 'o', name: 'n');

  group('JobRef', () {
    test('constructs with valid spec-<id> jobId', () {
      final j = JobRef(repo: repo, jobId: 'spec-abc-123');
      expect(j.jobId, 'spec-abc-123');
      expect(j.repo, repo);
    });

    test('single-segment id is valid', () {
      expect(
        () => JobRef(repo: repo, jobId: 'spec-42'),
        returnsNormally,
      );
    });

    test('equal fields produce equal instances', () {
      final a = JobRef(repo: repo, jobId: 'spec-a');
      final b = JobRef(repo: repo, jobId: 'spec-a');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different jobId makes instances unequal', () {
      final a = JobRef(repo: repo, jobId: 'spec-a');
      final b = JobRef(repo: repo, jobId: 'spec-b');
      expect(a, isNot(equals(b)));
    });

    test('toString includes the jobId', () {
      final j = JobRef(repo: repo, jobId: 'spec-xyz');
      expect(j.toString(), contains('spec-xyz'));
    });

    test('throws ArgumentError when jobId lacks spec- prefix', () {
      expect(
        () => JobRef(repo: repo, jobId: 'abc-123'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when jobId has uppercase letters', () {
      expect(
        () => JobRef(repo: repo, jobId: 'spec-ABC'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when jobId has invalid characters', () {
      expect(
        () => JobRef(repo: repo, jobId: 'spec-abc_123'),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on empty jobId', () {
      expect(
        () => JobRef(repo: repo, jobId: ''),
        throwsArgumentError,
      );
    });
  });
}
