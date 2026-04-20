import 'job_ref.dart';
import 'phase.dart';
import 'source_kind.dart';

/// A resolved job — its [ref], current [phase] derived from files on disk,
/// and the [sourceKind] of the spec being reviewed.
///
/// See IMPLEMENTATION.md §2.6 (ubiquitous language) and §4.3 (`SpecRepository`
/// returns `List<Job>` via `listOpenJobs`).
class Job {
  const Job({
    required this.ref,
    required this.phase,
    required this.sourceKind,
  });

  final JobRef ref;
  final Phase phase;
  final SourceKind sourceKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Job &&
          other.ref == ref &&
          other.phase == phase &&
          other.sourceKind == sourceKind;

  @override
  int get hashCode => Object.hash(ref, phase, sourceKind);

  @override
  String toString() =>
      'Job(ref: $ref, phase: ${phase.name}, sourceKind: ${sourceKind.name})';
}
