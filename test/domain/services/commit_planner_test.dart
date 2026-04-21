import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/source_kind.dart';
import 'package:gitmdannotations_tablet/domain/entities/spec_file.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/services/commit_planner.dart';
import 'package:gitmdannotations_tablet/domain/services/commit_planner_error.dart';
import 'package:gitmdannotations_tablet/domain/services/planned_write.dart';

const _specSha = 'a3f91c';

JobRef _job([String id = 'spec-auth']) => JobRef(
      repo: const RepoRef(owner: 'o', name: 'r'),
      jobId: id,
    );

SpecFile _md({String sha = _specSha, String id = 'spec-auth'}) => SpecFile(
      path: 'jobs/pending/$id/02-spec.md',
      sha: sha,
      contents: '# whatever',
      sourceKind: SourceKind.markdown,
    );

SpecFile _pdf({String sha = _specSha, String id = 'spec-auth'}) => SpecFile(
      path: 'jobs/pending/$id/spec.pdf',
      sha: sha,
      contents: '',
      sourceKind: SourceKind.pdf,
    );

StrokeGroup _mdGroup({String sha = _specSha, int line = 10}) => StrokeGroup(
      id: 'g1',
      anchor: MarkdownAnchor(lineNumber: line, sourceSha: sha),
      timestamp: DateTime.utc(2026, 4, 20),
      strokes: [
        Stroke(
          points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
          color: '#DC2626',
          strokeWidth: 2,
        ),
      ],
    );

StrokeGroup _pdfGroup({String sha = _specSha, int page = 1}) => StrokeGroup(
      id: 'g1',
      anchor: PdfAnchor(
        page: page,
        bbox: const Rect(left: 0, top: 0, right: 10, bottom: 10),
        sourceSha: sha,
      ),
      timestamp: DateTime.utc(2026, 4, 20),
      strokes: [
        Stroke(
          points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
          color: '#DC2626',
          strokeWidth: 2,
        ),
      ],
    );

Uint8List _png([int b = 0x89]) => Uint8List.fromList([b, 0x50, 0x4E, 0x47]);

void main() {
  group('planReview markdown', () {
    test('writes exactly 03-review.md, annotations svg+png, and updated spec',
        () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job(),
        source: _md(),
        reviewMd: '# Review',
        markdownAnnotations:
            MarkdownAnnotations(svg: '<svg/>', png: _png()),
        pdfAnnotations: null,
        updatedSpecOrSidecar: '# spec + changelog',
        strokeGroups: [_mdGroup()],
      );
      expect(
        plan.writes.map((w) => w.path).toSet(),
        {
          'jobs/pending/spec-auth/03-review.md',
          'jobs/pending/spec-auth/03-annotations.svg',
          'jobs/pending/spec-auth/03-annotations.png',
          'jobs/pending/spec-auth/02-spec.md',
        },
      );
    });

    test('commit message is "review: <jobId>"', () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job('spec-auth-flow'),
        source: _md(id: 'spec-auth-flow'),
        reviewMd: '# Review',
        markdownAnnotations:
            MarkdownAnnotations(svg: '<svg/>', png: _png()),
        pdfAnnotations: null,
        updatedSpecOrSidecar: '# spec',
        strokeGroups: const [],
      );
      expect(plan.message, 'review: spec-auth-flow');
    });

    test('empty stroke groups still emits the four write paths', () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job(),
        source: _md(),
        reviewMd: '# Review',
        markdownAnnotations:
            MarkdownAnnotations(svg: '<svg/>', png: _png()),
        pdfAnnotations: null,
        updatedSpecOrSidecar: '# spec',
        strokeGroups: const [],
      );
      expect(plan.writes.length, 4);
    });

    test('PNG is emitted as a binary write carrying the exact bytes', () {
      const planner = CommitPlanner();
      final bytes = _png(0xAB);
      final plan = planner.planReview(
        job: _job(),
        source: _md(),
        reviewMd: '# Review',
        markdownAnnotations:
            MarkdownAnnotations(svg: '<svg/>', png: bytes),
        pdfAnnotations: null,
        updatedSpecOrSidecar: '# spec',
        strokeGroups: const [],
      );
      final png = plan.writes
              .firstWhere((w) => w.path.endsWith('.png'))
          as PlannedBinaryWrite;
      expect(png.bytes, bytes);
    });
  });

  group('planReview pdf', () {
    test('emits per-page pairs + review md + sidecar CHANGELOG.md', () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job(),
        source: _pdf(),
        reviewMd: '# Review',
        markdownAnnotations: null,
        pdfAnnotations: PdfAnnotationSet(
          svgByPage: {1: '<svg/>', 2: '<svg/>', 3: '<svg/>'},
          pngByPage: {1: _png(), 2: _png(), 3: _png()},
        ),
        updatedSpecOrSidecar: '## Changelog',
        strokeGroups: [
          _pdfGroup(page: 1),
          _pdfGroup(page: 2),
          _pdfGroup(page: 3),
        ],
      );
      expect(
        plan.writes.map((w) => w.path).toSet(),
        {
          'jobs/pending/spec-auth/03-review.md',
          'jobs/pending/spec-auth/03-annotations-p1.svg',
          'jobs/pending/spec-auth/03-annotations-p1.png',
          'jobs/pending/spec-auth/03-annotations-p2.svg',
          'jobs/pending/spec-auth/03-annotations-p2.png',
          'jobs/pending/spec-auth/03-annotations-p3.svg',
          'jobs/pending/spec-auth/03-annotations-p3.png',
          'jobs/pending/spec-auth/CHANGELOG.md',
        },
      );
    });

    test('page numbering is 1-based with no zero-padding', () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job(),
        source: _pdf(),
        reviewMd: '# Review',
        markdownAnnotations: null,
        pdfAnnotations: PdfAnnotationSet(
          svgByPage: {1: '<svg/>', 2: '<svg/>', 10: '<svg/>'},
          pngByPage: {1: _png(), 2: _png(), 10: _png()},
        ),
        updatedSpecOrSidecar: '## Changelog',
        strokeGroups: const [],
      );
      final paths = plan.writes.map((w) => w.path).toSet();
      expect(
        paths.intersection({
          'jobs/pending/spec-auth/03-annotations-p1.svg',
          'jobs/pending/spec-auth/03-annotations-p2.svg',
          'jobs/pending/spec-auth/03-annotations-p10.svg',
        }).length,
        3,
      );
    });
  });

  group('planReview invariants', () {
    test('anchorKindMismatch when md spec receives a PdfAnchor group', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _md(),
          reviewMd: '# R',
          markdownAnnotations:
              MarkdownAnnotations(svg: '<svg/>', png: _png()),
          pdfAnnotations: null,
          updatedSpecOrSidecar: '# spec',
          strokeGroups: [_pdfGroup()],
        ),
        throwsA(isA<CommitPlannerAnchorKindMismatch>()),
      );
    });

    test('anchorShaMismatch when a stroke group anchor has a stale sha', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _md(sha: 'newsha'),
          reviewMd: '# R',
          markdownAnnotations:
              MarkdownAnnotations(svg: '<svg/>', png: _png()),
          pdfAnnotations: null,
          updatedSpecOrSidecar: '# spec',
          strokeGroups: [_mdGroup(sha: 'oldsha')],
        ),
        throwsA(isA<CommitPlannerAnchorShaMismatch>()),
      );
    });

    test('pdfPageSetMismatch when svg pages != png pages', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _pdf(),
          reviewMd: '# R',
          markdownAnnotations: null,
          pdfAnnotations: PdfAnnotationSet(
            svgByPage: {1: '<svg/>', 2: '<svg/>'},
            pngByPage: {1: _png()},
          ),
          updatedSpecOrSidecar: '# s',
          strokeGroups: const [],
        ),
        throwsA(isA<CommitPlannerPdfPageSetMismatch>()),
      );
    });

    test('missingPair when both markdown and pdf annotations are null', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _md(),
          reviewMd: '# R',
          markdownAnnotations: null,
          pdfAnnotations: null,
          updatedSpecOrSidecar: '# s',
          strokeGroups: const [],
        ),
        throwsA(isA<CommitPlannerMissingPair>()),
      );
    });

    test('throws when markdown spec supplied with pdfAnnotations', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _md(),
          reviewMd: '# R',
          markdownAnnotations: null,
          pdfAnnotations: PdfAnnotationSet(
            svgByPage: {1: '<svg/>'},
            pngByPage: {1: _png()},
          ),
          updatedSpecOrSidecar: '# s',
          strokeGroups: const [],
        ),
        throwsA(isA<CommitPlannerMissingPair>()),
      );
    });

    test('throws when pdf spec supplied with markdownAnnotations', () {
      const planner = CommitPlanner();
      expect(
        () => planner.planReview(
          job: _job(),
          source: _pdf(),
          reviewMd: '# R',
          markdownAnnotations:
              MarkdownAnnotations(svg: '<svg/>', png: _png()),
          pdfAnnotations: null,
          updatedSpecOrSidecar: '# s',
          strokeGroups: const [],
        ),
        throwsA(isA<CommitPlannerMissingPair>()),
      );
    });
  });

  group('planApprove', () {
    test('markdown source: emits 05-approved + updated spec (two writes)',
        () {
      const planner = CommitPlanner();
      final plan = planner.planApprove(
        job: _job(),
        source: _md(),
        updatedSpecOrSidecar: '# spec with changelog',
      );
      expect(plan.writes.length, 2);
    });

    test('commit message is "approve: <jobId>"', () {
      const planner = CommitPlanner();
      final plan = planner.planApprove(
        job: _job('spec-auth-flow'),
        source: _md(id: 'spec-auth-flow'),
        updatedSpecOrSidecar: '# spec',
      );
      expect(plan.message, 'approve: spec-auth-flow');
    });

    test('05-approved content is an empty string', () {
      const planner = CommitPlanner();
      final plan = planner.planApprove(
        job: _job(),
        source: _md(),
        updatedSpecOrSidecar: '# spec',
      );
      final approved = plan.writes
              .firstWhere((w) => w.path.endsWith('/05-approved'))
          as PlannedTextWrite;
      expect(approved.contents, '');
    });

    test('updated spec write path matches source.path', () {
      const planner = CommitPlanner();
      final plan = planner.planApprove(
        job: _job(),
        source: _md(),
        updatedSpecOrSidecar: '# spec',
      );
      expect(
        plan.writes.map((w) => w.path),
        contains('jobs/pending/spec-auth/02-spec.md'),
      );
    });

    test('PDF source: writes 05-approved + CHANGELOG.md sidecar', () {
      const planner = CommitPlanner();
      final plan = planner.planApprove(
        job: _job(),
        source: _pdf(),
        updatedSpecOrSidecar: '## Changelog',
      );
      expect(
        plan.writes.map((w) => w.path).toSet(),
        {
          'jobs/pending/spec-auth/05-approved',
          'jobs/pending/spec-auth/CHANGELOG.md',
        },
      );
    });
  });

  group('path construction', () {
    test('all review writes are rooted at jobs/pending/<jobId>/', () {
      const planner = CommitPlanner();
      final plan = planner.planReview(
        job: _job('spec-xyz-1'),
        source: _md(id: 'spec-xyz-1'),
        reviewMd: '# R',
        markdownAnnotations:
            MarkdownAnnotations(svg: '<svg/>', png: _png()),
        pdfAnnotations: null,
        updatedSpecOrSidecar: '# s',
        strokeGroups: const [],
      );
      for (final w in plan.writes) {
        expect(w.path.startsWith('jobs/pending/spec-xyz-1/'), isTrue,
            reason: 'path ${w.path} not rooted under job folder');
      }
    });
  });
}
