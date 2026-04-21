import 'dart:typed_data';

import '../../domain/entities/canvas_size.dart';
import '../../domain/entities/changelog_entry.dart';
import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/source_kind.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/ports/clock_port.dart';
import '../../domain/ports/file_system_port.dart';
import '../../domain/ports/git_port.dart';
import '../../domain/ports/markdown_rasterizer_port.dart';
import '../../domain/ports/png_flattener_port.dart';
import '../../domain/services/annotation_pdf_composer.dart';
import '../../domain/services/annotation_sidecar_serializer.dart';
import '../../domain/services/changelog_writer.dart';
import '../../domain/services/commit_planner.dart';
import '../../domain/services/planned_write.dart';
import '../../domain/services/review_serializer.dart';
import '../../domain/services/svg_serializer.dart';
import '../../domain/services/open_question_extractor.dart';
import '../../ui/screens/annotation_canvas/main_content.dart'
    show kAnnotatedContentWidth;

/// Stateless composition of the domain-service stack for Submit Review and
/// Approve commits. Splitting this out keeps [ReviewController] focused on
/// state management — this class is a pure function of its ports and
/// services, and can be unit-tested by passing fakes directly (no
/// Riverpod).
class ReviewSubmitter {
  ReviewSubmitter({
    required Clock clock,
    required FileSystemPort fs,
    required GitPort git,
    required PngFlattener pngFlattener,
    required MarkdownRasterizerPort markdownRasterizer,
  })  : _clock = clock,
        _fs = fs,
        _git = git,
        _pngFlattener = pngFlattener,
        _markdownRasterizer = markdownRasterizer;

  final Clock _clock;
  final FileSystemPort _fs;
  final GitPort _git;
  final PngFlattener _pngFlattener;
  final MarkdownRasterizerPort _markdownRasterizer;

  /// Composes and commits the typed review per PRD §5.6 FR-1.25/1.26.
  ///
  /// Happy path: SvgSerializer → PngFlattener → ReviewSerializer →
  /// ChangelogWriter → CommitPlanner → GitPort.commit. Typed invariant
  /// failures from `CommitPlanner` (and any other exceptions at the
  /// boundary) propagate raw — the caller (ReviewController) owns the
  /// sealed-submission-state mapping.
  Future<Commit> submit({
    required JobRef job,
    required SpecFile source,
    required List<OpenQuestion> questions,
    required Map<String, String> answers,
    required String freeFormNotes,
    required List<StrokeGroup> strokeGroups,
    required GitIdentity identity,
  }) async {
    // Review body.
    final reviewMd = ReviewSerializer(clock: _clock).buildReviewMd(
      job: job,
      source: source,
      questions: questions,
      answers: answers,
      freeFormNotes: freeFormNotes,
      strokeGroups: strokeGroups,
    );

    // Annotation bundle for markdown path: legacy svg + png retained
    // for downstream tooling, new composite pdf + json sidecar added
    // per the canonical-width zoom-to-fill milestone.
    //
    // The PDF and JSON use canonical coords (page size = canonical
    // width × the raster's natural height from the mounted
    // RepaintBoundary); the SVG coords are untouched and match what the
    // on-screen InkOverlay captured.
    MarkdownAnnotations? markdownAnnotations;
    if (source.sourceKind == SourceKind.markdown) {
      final svgSource =
          SvgSource(sourceFile: source.path, sourceSha: source.sha);
      final svg = const SvgSerializer().serialize(strokeGroups, svgSource);
      // Rasterize first: its canonical dims also size the PNG flatten
      // so strokes at large canonical y (anywhere below the top 1024
      // canonical px, which is most of a real spec) stay on-canvas.
      final raster = await _markdownRasterizer.rasterize();
      // Clamp each axis at the GPU max texture for Picture.toImage
      // (used by PngFlattenerAdapter). For the PNG we care about
      // on-canvas strokes, not sampling density, so a gentle cap is
      // fine. Matches the rasterizer's [_kGpuMaxTexture] behavior.
      const double kGpuMaxTexture = 16384;
      final pngCanvas = CanvasSize(
        width: raster.canonicalWidth.clamp(1, kGpuMaxTexture),
        height: raster.canonicalHeight.clamp(1, kGpuMaxTexture),
      );
      final png = await _pngFlattener.flatten(
        groups: strokeGroups,
        canvas: pngCanvas,
      );
      final pdf = await const AnnotationPdfComposer().compose(
        backgroundPng: raster.pngBytes,
        canonicalWidth: raster.canonicalWidth,
        canonicalHeight: raster.canonicalHeight,
        groups: strokeGroups,
      );
      final json = const AnnotationSidecarSerializer(
        canonicalWidth: kAnnotatedContentWidth,
      ).serialize(strokeGroups, svgSource);
      markdownAnnotations = MarkdownAnnotations(
        svg: svg,
        png: png,
        pdf: pdf,
        json: json,
      );
    }

    final updatedChangelog = await _composeChangelog(
      job: job,
      source: source,
      description: 'Submitted review of ${_basename(source.path)}.',
    );

    final plan = const CommitPlanner().planReview(
      job: job,
      source: source,
      reviewMd: reviewMd,
      markdownAnnotations: markdownAnnotations,
      pdfAnnotations: null,
      updatedSpecOrSidecar: updatedChangelog,
      strokeGroups: strokeGroups,
    );

    return _git.commit(
      files: plan.writes.map(_toFileWrite).toList(),
      message: plan.message,
      id: identity,
      branch: 'claude-jobs',
    );
  }

  /// Composes and commits the Approve commit per PRD §5.6 FR-1.27/1.28.
  /// Writes an empty `05-approved` marker + appends a changelog entry;
  /// no new annotations, no PNG flatten.
  Future<Commit> approve({
    required JobRef job,
    required SpecFile source,
    required GitIdentity identity,
  }) async {
    final updatedChangelog = await _composeChangelog(
      job: job,
      source: source,
      description: 'Approved ${_basename(source.path)} for implementation.',
    );
    final plan = const CommitPlanner().planApprove(
      job: job,
      source: source,
      updatedSpecOrSidecar: updatedChangelog,
    );
    return _git.commit(
      files: plan.writes.map(_toFileWrite).toList(),
      message: plan.message,
      id: identity,
      branch: 'claude-jobs',
    );
  }

  Future<String> _composeChangelog({
    required JobRef job,
    required SpecFile source,
    required String description,
  }) async {
    final existing = await _readExisting(
      source.sourceKind == SourceKind.pdf
          ? 'jobs/pending/${job.jobId}/CHANGELOG.md'
          : source.path,
    );
    return const ChangelogWriter().append(
      existing.isEmpty && source.sourceKind == SourceKind.markdown
          ? source.contents
          : existing,
      ChangelogEntry(
        timestamp: _clock.now(),
        author: 'tablet',
        description: description,
      ),
    );
  }

  Future<String> _readExisting(String path) async {
    try {
      return await _fs.readString(path);
    } on FsNotFound {
      return '';
    }
  }

  String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  FileWrite _toFileWrite(PlannedWrite p) => switch (p) {
        PlannedTextWrite(:final path, :final contents) =>
          FileWrite(path: path, contents: contents),
        PlannedBinaryWrite(:final path, :final bytes) =>
          FileWrite(path: path, contents: '', bytes: Uint8List.fromList(bytes)),
      };
}
