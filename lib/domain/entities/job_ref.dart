import 'repo_ref.dart';

/// A reference to a single job folder `jobs/pending/spec-<id>/` on the
/// `claude-jobs` branch of [repo].
///
/// [jobId] must match `^spec-[a-z0-9-]+$` (IMPLEMENTATION.md §3.2). Invalid
/// ids are rejected in the constructor so downstream services can assume the
/// shape.
class JobRef {
  JobRef({required this.repo, required this.jobId}) {
    if (!_pattern.hasMatch(jobId)) {
      throw ArgumentError.value(
        jobId,
        'jobId',
        'must match ${_pattern.pattern}',
      );
    }
  }

  final RepoRef repo;
  final String jobId;

  static final RegExp _pattern = RegExp(r'^spec-[a-z0-9-]+$');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobRef && other.repo == repo && other.jobId == jobId;

  @override
  int get hashCode => Object.hash(repo, jobId);

  @override
  String toString() => 'JobRef(repo: $repo, jobId: $jobId)';
}
