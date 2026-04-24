import '../entities/anchor.dart';
import '../entities/job_ref.dart';
import '../entities/source_kind.dart';
import '../entities/spec_file.dart';
import '../entities/stroke_group.dart';
import 'commit_planner_error.dart';
import 'planned_write.dart';

/// Plans atomic file writes for the two tablet-side commits (IMPLEMENTATION.md
/// §4.7 / PRD §5.6): **Submit Review** (`review: <jobId>`) and **Approve**
/// (`approve: <jobId>`). Pure domain — zero I/O, zero Flutter.
///
/// PNG vs text: `GitPort.FileWrite` stores `String` which can't round-trip PNG
/// bytes. Rather than hack the encoding or mutate the port from this task,
/// this service emits its own sealed [PlannedWrite] hierarchy. The
/// `ReviewController` (T7) adapts these to `FileWrite`s; a future port
/// revision may grow a bytes variant.
///
/// §3.7 invariants throw typed [CommitPlannerError]s.
///
/// §3.7 invariant split (collaboration note):
/// [CommitPlanner] enforces anchor kind/SHA match, PDF page parity, and
/// annotation pairing. It does NOT verify the SVG payload's internal
/// `data-source-sha` attribute — that belongs to `SvgSerializer`
/// (`lib/domain/services/svg_serializer.dart`); callers wiring the two must
/// pass `SvgSource.sourceSha` == `SpecFile.sha`. It also does NOT verify
/// that [updatedSpecOrSidecar] contains the appended changelog line — that
/// is `ChangelogWriter`'s concern; callers compose the two.
class CommitPlanner {
  const CommitPlanner();

  /// Plan **Submit Review**. [updatedSpecOrSidecar] is the full text of
  /// `02-spec.md` (md) or `CHANGELOG.md` (pdf sidecar), with the changelog
  /// line already appended by the caller.
  PlannedCommit planReview({
    required JobRef job,
    required SpecFile source,
    required String reviewMd,
    required MarkdownAnnotations? markdownAnnotations,
    required PdfAnnotationSet? pdfAnnotations,
    required String updatedSpecOrSidecar,
    required List<StrokeGroup> strokeGroups,
  }) {
    _assertAnnotationPairing(source, markdownAnnotations, pdfAnnotations);
    _assertAnchorsMatchSource(source, strokeGroups);
    return PlannedCommit(
      message: 'review: ${job.jobId}',
      writes: [
        PlannedTextWrite(path: _p(job, '03-review.md'), contents: reviewMd),
        ..._annotationWrites(job, source, markdownAnnotations, pdfAnnotations),
        PlannedTextWrite(
          path: _changelogTarget(job, source),
          contents: updatedSpecOrSidecar,
        ),
      ],
    );
  }

  /// Plan **Approve**: empty `05-approved` + updated spec/sidecar.
  // Skips anchor / annotation-pairing invariants: approve introduces no new annotations.
  PlannedCommit planApprove({
    required JobRef job,
    required SpecFile source,
    required String updatedSpecOrSidecar,
  }) =>
      PlannedCommit(
        message: 'approve: ${job.jobId}',
        writes: [
          PlannedTextWrite(path: _p(job, '05-approved'), contents: ''),
          PlannedTextWrite(
            path: _changelogTarget(job, source),
            contents: updatedSpecOrSidecar,
          ),
        ],
      );

  Iterable<PlannedWrite> _annotationWrites(
    JobRef job,
    SpecFile source,
    MarkdownAnnotations? md,
    PdfAnnotationSet? pdf,
  ) sync* {
    switch (source.sourceKind) {
      case SourceKind.markdown:
        // Four artifacts per submit:
        //   .svg — legacy vector (IMPLEMENTATION.md §3.4)
        //   .png — legacy flattened raster (§4.5)
        //   .pdf — composite markdown-background + vector-stroke overlay
        //   .json — format-agnostic sidecar (anchors + stroke points)
        // The `.svg` + `.png` pair stays until downstream tooling is
        // confirmed PDF/JSON-ready; then the planner trims to just the
        // new pair.
        yield PlannedTextWrite(
            path: _p(job, '03-annotations.svg'), contents: md!.svg);
        yield PlannedBinaryWrite(
            path: _p(job, '03-annotations.png'), bytes: md.png);
        yield PlannedBinaryWrite(
            path: _p(job, '03-annotations.pdf'), bytes: md.pdf);
        yield PlannedTextWrite(
            path: _p(job, '03-annotations.json'), contents: md.json);
      case SourceKind.pdf:
        final pages = pdf!.svgByPage.keys.toList()..sort();
        for (final page in pages) {
          yield PlannedTextWrite(
              path: _p(job, '03-annotations-p$page.svg'),
              contents: pdf.svgByPage[page]!);
          yield PlannedBinaryWrite(
              path: _p(job, '03-annotations-p$page.png'),
              bytes: pdf.pngByPage[page]!);
        }
      case SourceKind.svg:
        // Non-annotatable — the SVG reader never offers Submit; pairing
        // guard asserts md == null && pdf == null so no artifacts are
        // emitted.
        return;
    }
  }

  String _changelogTarget(JobRef job, SpecFile source) {
    // PDF and SVG both use a sibling CHANGELOG.md because their source
    // files can't host an embedded `## Changelog` section. Markdown
    // folds the changelog back into the spec's own trailing section.
    switch (source.sourceKind) {
      case SourceKind.pdf:
      case SourceKind.svg:
        return _p(job, 'CHANGELOG.md');
      case SourceKind.markdown:
        // `source.path` is an absolute filesystem path
        // (`<workdir>/jobs/pending/<jobId>/02-spec.md`) because
        // SpecRepository builds it by joining `workdir`. Using it
        // verbatim as the commit target makes git store a file at the
        // full absolute path (minus leading `/`) INSIDE the repo tree,
        // polluting the branch with a deep nested dupe of the real
        // spec. Only the last path segment is meaningful — the
        // jobs-pending prefix is stable (see [_p]) and the basename is
        // either `02-spec.md` or `04-spec-v<N>.md` per
        // IMPLEMENTATION.md §3.2.
        return _p(job, _basename(source.path));
    }
  }

  String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String _p(JobRef job, String filename) =>
      'jobs/pending/${job.jobId}/$filename';

  void _assertAnnotationPairing(
    SpecFile source,
    MarkdownAnnotations? md,
    PdfAnnotationSet? pdf,
  ) {
    switch (source.sourceKind) {
      case SourceKind.markdown:
        if (md == null || pdf != null) {
          throw const CommitPlannerMissingPair(
              'markdown source requires markdownAnnotations and null pdfAnnotations');
        }
      case SourceKind.pdf:
        if (pdf == null || md != null) {
          throw const CommitPlannerMissingPair(
              'pdf source requires pdfAnnotations and null markdownAnnotations');
        }
        _assertPdfPageSetsMatch(pdf);
      case SourceKind.svg:
        if (md != null || pdf != null) {
          throw const CommitPlannerMissingPair(
              'svg source is non-annotatable; markdownAnnotations and pdfAnnotations must both be null');
        }
    }
  }

  void _assertPdfPageSetsMatch(PdfAnnotationSet set) {
    final svg = set.svgByPage.keys.toSet();
    final png = set.pngByPage.keys.toSet();
    if (svg.length != png.length || !svg.containsAll(png)) {
      throw CommitPlannerPdfPageSetMismatch(svgPages: svg, pngPages: png);
    }
  }

  void _assertAnchorsMatchSource(SpecFile source, List<StrokeGroup> groups) {
    for (final g in groups) {
      final anchor = g.anchor;
      final kindOk = switch (source.sourceKind) {
        SourceKind.markdown => anchor is MarkdownAnchor,
        SourceKind.pdf => anchor is PdfAnchor,
        // SVG is non-annotatable — any stroke with an SVG source is a
        // bug in the caller.
        SourceKind.svg => false,
      };
      if (!kindOk) throw CommitPlannerAnchorKindMismatch(groupId: g.id);
      if (anchor.sourceSha != source.sha) {
        throw CommitPlannerAnchorShaMismatch(
          groupId: g.id,
          anchorSha: anchor.sourceSha,
          specSha: source.sha,
        );
      }
    }
  }
}
