import 'dart:typed_data';

import '../entities/anchor.dart';
import '../entities/job_ref.dart';
import '../entities/source_kind.dart';
import '../entities/spec_file.dart';
import '../entities/stroke_group.dart';

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

  String _changelogTarget(JobRef job, SpecFile source) =>
      source.sourceKind == SourceKind.pdf
          ? _p(job, 'CHANGELOG.md')
          : source.path;

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

/// Commit message + writes applied atomically as one commit.
class PlannedCommit {
  const PlannedCommit({required this.message, required this.writes});
  final String message;
  final List<PlannedWrite> writes;
}

/// Sealed root of the two write variants; see [CommitPlanner] for motivation.
sealed class PlannedWrite {
  const PlannedWrite({required this.path});
  final String path;
}

class PlannedTextWrite extends PlannedWrite {
  const PlannedTextWrite({required super.path, required this.contents});
  final String contents;
}

class PlannedBinaryWrite extends PlannedWrite {
  const PlannedBinaryWrite({required super.path, required this.bytes});
  final Uint8List bytes;
}

/// Markdown annotation pair: git-diffable SVG + flattened PNG.
class MarkdownAnnotations {
  const MarkdownAnnotations({required this.svg, required this.png});
  final String svg;
  final Uint8List png;
}

/// PDF annotation set keyed by 1-based page number. Keys must match.
class PdfAnnotationSet {
  const PdfAnnotationSet({required this.svgByPage, required this.pngByPage});
  final Map<int, String> svgByPage;
  final Map<int, Uint8List> pngByPage;
}

/// Sealed root of typed §3.7 invariant violations.
sealed class CommitPlannerError implements Exception {
  const CommitPlannerError();
}

class CommitPlannerAnchorKindMismatch extends CommitPlannerError {
  const CommitPlannerAnchorKindMismatch({required this.groupId});
  final String groupId;
}

class CommitPlannerAnchorShaMismatch extends CommitPlannerError {
  const CommitPlannerAnchorShaMismatch({
    required this.groupId,
    required this.anchorSha,
    required this.specSha,
  });
  final String groupId;
  final String anchorSha;
  final String specSha;
}

class CommitPlannerPdfPageSetMismatch extends CommitPlannerError {
  const CommitPlannerPdfPageSetMismatch(
      {required this.svgPages, required this.pngPages});
  final Set<int> svgPages;
  final Set<int> pngPages;
}

class CommitPlannerMissingPair extends CommitPlannerError {
  const CommitPlannerMissingPair(this.reason);
  final String reason;
}
