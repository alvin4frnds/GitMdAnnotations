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
    if (source.sourceKind == SourceKind.markdown) {
      yield PlannedTextWrite(
          path: _p(job, '03-annotations.svg'), contents: md!.svg);
      yield PlannedBinaryWrite(
          path: _p(job, '03-annotations.png'), bytes: md.png);
      return;
    }
    final pages = pdf!.svgByPage.keys.toList()..sort();
    for (final page in pages) {
      yield PlannedTextWrite(
          path: _p(job, '03-annotations-p$page.svg'),
          contents: pdf.svgByPage[page]!);
      yield PlannedBinaryWrite(
          path: _p(job, '03-annotations-p$page.png'),
          bytes: pdf.pngByPage[page]!);
    }
  }

  String _changelogTarget(JobRef job, SpecFile source) {
    if (source.sourceKind == SourceKind.pdf) {
      return _p(job, 'CHANGELOG.md');
    }
    // `source.path` is an absolute filesystem path
    // (`<workdir>/jobs/pending/<jobId>/02-spec.md`) because SpecRepository
    // builds it by joining `workdir`. Using it verbatim as the commit
    // target makes git store a file at the full absolute path (minus
    // leading `/`) INSIDE the repo tree, polluting the branch with
    // a deep nested dupe of the real spec. Only the last path segment
    // is meaningful for the commit — the jobs-pending prefix is stable
    // (see [_p]) and the basename is either `02-spec.md` or
    // `04-spec-v<N>.md` per IMPLEMENTATION.md §3.2.
    return _p(job, _basename(source.path));
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
    final isMd = source.sourceKind == SourceKind.markdown;
    if (isMd && (md == null || pdf != null)) {
      throw const CommitPlannerMissingPair(
          'markdown source requires markdownAnnotations and null pdfAnnotations');
    }
    if (!isMd && (pdf == null || md != null)) {
      throw const CommitPlannerMissingPair(
          'pdf source requires pdfAnnotations and null markdownAnnotations');
    }
    if (!isMd) _assertPdfPageSetsMatch(pdf!);
  }

  void _assertPdfPageSetsMatch(PdfAnnotationSet set) {
    final svg = set.svgByPage.keys.toSet();
    final png = set.pngByPage.keys.toSet();
    if (svg.length != png.length || !svg.containsAll(png)) {
      throw CommitPlannerPdfPageSetMismatch(svgPages: svg, pngPages: png);
    }
  }

  void _assertAnchorsMatchSource(SpecFile source, List<StrokeGroup> groups) {
    final isMd = source.sourceKind == SourceKind.markdown;
    for (final g in groups) {
      final anchor = g.anchor;
      final kindOk = isMd ? anchor is MarkdownAnchor : anchor is PdfAnchor;
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
