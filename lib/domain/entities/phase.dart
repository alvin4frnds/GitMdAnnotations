/// The current state of a job folder, derived from the files present inside
/// `jobs/pending/spec-<id>/` on the `claude-jobs` branch.
///
/// See IMPLEMENTATION.md §2.6 and §4.3. `Phase.resolve` is the `PhaseResolver`
/// domain service as a static helper; it can be extracted to a free function
/// later without touching callers.
enum Phase {
  spec,
  review,
  revised,
  approved;

  /// Truth table per §4.3:
  /// - contains `05-approved` -> approved
  /// - else any `04-spec-v*.md` -> revised
  /// - else `03-review.md` -> review
  /// - else `02-spec.md` -> spec
  /// - otherwise throws [ArgumentError].
  static Phase resolve(Set<String> filenames) {
    if (filenames.contains('05-approved')) {
      return Phase.approved;
    }
    final hasRevision = filenames.any(_isRevisionFile);
    if (hasRevision) {
      return Phase.revised;
    }
    if (filenames.contains('03-review.md')) {
      return Phase.review;
    }
    if (filenames.contains('02-spec.md')) {
      return Phase.spec;
    }
    throw ArgumentError('no recognised phase files');
  }

  static final RegExp _revisionPattern = RegExp(r'^04-spec-v\d+\.md$');

  static bool _isRevisionFile(String name) => _revisionPattern.hasMatch(name);
}
