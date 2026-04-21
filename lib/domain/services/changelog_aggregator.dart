import '../entities/changelog_entry.dart';
import '../entities/job_ref.dart';
import '../entities/repo_ref.dart';
import 'spec_repository.dart';

/// One [ChangelogEntry] tagged with the [JobRef] it was sourced from.
///
/// The timeline on the ChangelogViewer screen (IMPLEMENTATION.md §6.4 /
/// PRD §5.9 FR-1.37) is a flat, reverse-chronological list across every
/// open job; the job provenance travels with each entry so the row can
/// render the originating jobId alongside the date + description.
class DatedChangelogEntry {
  const DatedChangelogEntry({required this.job, required this.entry});

  final JobRef job;
  final ChangelogEntry entry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatedChangelogEntry && other.job == job && other.entry == entry;

  @override
  int get hashCode => Object.hash(job, entry);

  @override
  String toString() => 'DatedChangelogEntry(job: ${job.jobId}, entry: $entry)';
}

/// Aggregates `## Changelog` entries across every open job in a repo into
/// a single timeline view.
///
/// Thin composition over [SpecRepository.listOpenJobs] +
/// [SpecRepository.readChangelog]; kept separate from `SpecRepository`
/// because its output shape ([DatedChangelogEntry]) and sort semantics are
/// specific to the viewer screen — pushing it into the repository would
/// bloat the core spec-loading API for a single consumer (M1d-T1).
class ChangelogAggregator {
  const ChangelogAggregator(this._repo);

  final SpecRepository _repo;

  /// Collects every parseable `## Changelog` entry from every open job
  /// under [repo], newest-first by timestamp. Jobs with no changelog (or
  /// with a malformed section that fails [parseChangelog]) are silently
  /// skipped so a single bad spec doesn't blank the whole timeline.
  ///
  /// Sort is stable across entries with the same timestamp — insertion
  /// order within a job is preserved, and jobs appear in the order
  /// returned by [SpecRepository.listOpenJobs].
  Future<List<DatedChangelogEntry>> allChangelogs(RepoRef repo) async {
    final jobs = await _repo.listOpenJobs(repo);
    final all = <DatedChangelogEntry>[];
    for (final job in jobs) {
      final List<ChangelogEntry> entries;
      try {
        entries = await _repo.readChangelog(job.ref);
      } on FormatException {
        // Malformed `- YYYY-MM-DD …` line somewhere in the section.
        // Swallow so one broken file can't hide every other job's history;
        // the writer / commit hook is the appropriate place to catch this.
        continue;
      }
      for (final entry in entries) {
        all.add(DatedChangelogEntry(job: job.ref, entry: entry));
      }
    }
    // Stable reverse-chronological sort. `List.sort` is not guaranteed
    // stable in Dart, so fall back to an index-aware comparator.
    final indexed = [
      for (var i = 0; i < all.length; i++) (i, all[i]),
    ];
    indexed.sort((a, b) {
      final byTime = b.$2.entry.timestamp.compareTo(a.$2.entry.timestamp);
      if (byTime != 0) return byTime;
      return a.$1.compareTo(b.$1);
    });
    return List.unmodifiable([for (final e in indexed) e.$2]);
  }
}
