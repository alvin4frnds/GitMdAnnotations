import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/source_kind.dart';
import 'package:gitmdannotations_tablet/domain/entities/spec_file.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/ports/clock_port.dart';
import 'package:gitmdannotations_tablet/domain/services/open_question_extractor.dart';
import 'package:gitmdannotations_tablet/domain/services/review_serializer.dart';

String _readGolden(String name) =>
    File('test/golden/$name').readAsStringSync();

JobRef _job(String id) => JobRef(
      repo: const RepoRef(owner: 'o', name: 'r'),
      jobId: id,
    );

SpecFile _md({required String sha}) => SpecFile(
      path: 'jobs/pending/spec-auth/02-spec.md',
      sha: sha,
      contents: '# whatever',
      sourceKind: SourceKind.markdown,
    );

SpecFile _pdf({required String sha}) => SpecFile(
      path: 'jobs/pending/spec-auth/spec.pdf',
      sha: sha,
      contents: '',
      sourceKind: SourceKind.pdf,
    );

StrokeGroup _mdGroup({required int line, required String ts}) => StrokeGroup(
      id: 'ignored',
      anchor: MarkdownAnchor(lineNumber: line, sourceSha: 'a3f91c'),
      timestamp: DateTime.parse(ts),
      strokes: [
        Stroke(
          points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
          color: '#DC2626',
          strokeWidth: 2,
        ),
      ],
    );

StrokeGroup _pdfGroup({required int page, required String ts}) => StrokeGroup(
      id: 'ignored',
      anchor: PdfAnchor(
        page: page,
        bbox: const Rect(left: 0, top: 0, right: 10, bottom: 10),
        sourceSha: 'deadbeef',
      ),
      timestamp: DateTime.parse(ts),
      strokes: [
        Stroke(
          points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
          color: '#DC2626',
          strokeWidth: 2,
        ),
      ],
    );

void main() {
  group('ReviewSerializer — golden: markdown happy path', () {
    test('matches test/golden/review_markdown_happy_path.md', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-auth'),
        source: _md(sha: 'a3f91c'),
        questions: const [
          OpenQuestion(
            id: 'Q1',
            body: 'Should auth flow support magic links?',
          ),
          OpenQuestion(id: 'Q2', body: 'Session store: Redis or Postgres?'),
        ],
        answers: const {
          'Q1': 'Yes, but only as fallback after TOTP. '
              'See stroke group A at line 47.',
          'Q2': 'Postgres. See stroke group B at line 102.',
        },
        freeFormNotes: 'Auth section needs a diagram before revision.',
        strokeGroups: [
          _mdGroup(line: 47, ts: '2026-04-20T09:14:22Z'),
          _mdGroup(line: 102, ts: '2026-04-20T09:18:05Z'),
        ],
      );

      expect(out, _readGolden('review_markdown_happy_path.md'));
    });
  });

  group('ReviewSerializer — golden: pdf happy path', () {
    test('matches test/golden/review_pdf_happy_path.md', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-onboarding'),
        source: _pdf(sha: 'deadbeef'),
        questions: const [
          OpenQuestion(id: 'Q1', body: 'Does the PDF section 3 match v2 scope?'),
        ],
        answers: const {
          'Q1': 'Partly. See stroke group A on page 3.',
        },
        freeFormNotes: '',
        strokeGroups: [_pdfGroup(page: 3, ts: '2026-04-20T09:20:00Z')],
      );

      expect(out, _readGolden('review_pdf_happy_path.md'));
    });
  });

  group('ReviewSerializer — golden: zero stroke groups', () {
    test('matches test/golden/review_zero_strokes.md (no Spatial refs)', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-noink'),
        source: _md(sha: 'cafebabe'),
        questions: const [
          OpenQuestion(id: 'Q1', body: 'Any open questions?'),
          OpenQuestion(id: 'Q2', body: 'Anything else?'),
        ],
        answers: const {
          'Q1': 'No.',
          'Q2': 'Also no.',
        },
        freeFormNotes: 'Overall the spec looks solid.',
        strokeGroups: const [],
      );

      expect(out, _readGolden('review_zero_strokes.md'));
    });
  });

  group('ReviewSerializer — golden: missing answer', () {
    test('matches test/golden/review_missing_answer.md '
        '(Q2 rendered as empty quote)', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-half'),
        source: _md(sha: 'feedface'),
        questions: const [
          OpenQuestion(id: 'Q1', body: 'First question?'),
          OpenQuestion(id: 'Q2', body: 'Second question?'),
        ],
        answers: const {
          'Q1': 'Answer to first.',
        },
        freeFormNotes: '',
        strokeGroups: [_mdGroup(line: 5, ts: '2026-04-20T09:10:00Z')],
      );

      expect(out, _readGolden('review_missing_answer.md'));
    });
  });

  group('ReviewSerializer — golden: multiple stroke groups', () {
    test('matches test/golden/review_multi_group.md (letters A, B, C)', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-triple'),
        source: _md(sha: 'abc123'),
        questions: const [
          OpenQuestion(id: 'Q1', body: 'Any concerns?'),
        ],
        answers: const {
          'Q1': 'See stroke groups A, B, C.',
        },
        freeFormNotes: '',
        strokeGroups: [
          _mdGroup(line: 10, ts: '2026-04-20T09:10:00Z'),
          _mdGroup(line: 20, ts: '2026-04-20T09:11:00Z'),
          _mdGroup(line: 30, ts: '2026-04-20T09:12:00Z'),
        ],
      );

      expect(out, _readGolden('review_multi_group.md'));
    });
  });

  group('ReviewSerializer — zero questions', () {
    test('empty questions list suppresses the Answers section entirely', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-noqs'),
        source: _md(sha: 'abc'),
        questions: const [],
        answers: const <String, String>{},
        freeFormNotes: 'Spec reads cleanly; no open questions.',
        strokeGroups: [_mdGroup(line: 12, ts: '2026-04-20T09:00:00Z')],
      );

      expect(out, isNot(contains('## Answers to open questions')));
      // Sanity: the rest of the document is still well-formed.
      expect(out, contains('## Free-form notes'));
      expect(out, contains('## Spatial references'));
    });
  });

  group('ReviewSerializer — stroke-group letter overflow', () {
    test('27 stroke groups throws StateError with actionable message', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);
      final groups = List<StrokeGroup>.generate(
        27,
        (i) => _mdGroup(line: i + 1, ts: '2026-04-20T09:00:00Z'),
      );

      expect(
        () => serializer.buildReviewMd(
          job: _job('spec-overflow'),
          source: _md(sha: 'abc'),
          questions: const [],
          answers: const {},
          freeFormNotes: '',
          strokeGroups: groups,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('26'),
          ),
        ),
      );
    });

    test('26 stroke groups succeeds and last letter is Z', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);
      final groups = List<StrokeGroup>.generate(
        26,
        (i) => _mdGroup(line: i + 1, ts: '2026-04-20T09:00:00Z'),
      );

      final out = serializer.buildReviewMd(
        job: _job('spec-max'),
        source: _md(sha: 'abc'),
        questions: const [],
        answers: const {},
        freeFormNotes: '',
        strokeGroups: groups,
      );

      expect(out, contains('- Stroke group Z → line 26'));
    });
  });

  group('ReviewSerializer — ordering', () {
    test('stroke groups emit in list order, not sorted by anchor line', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-order'),
        source: _md(sha: 'abc'),
        questions: const [],
        answers: const {},
        freeFormNotes: '',
        strokeGroups: [
          _mdGroup(line: 300, ts: '2026-04-20T09:00:00Z'),
          _mdGroup(line: 100, ts: '2026-04-20T09:01:00Z'),
          _mdGroup(line: 200, ts: '2026-04-20T09:02:00Z'),
        ],
      );

      final aIdx = out.indexOf('Stroke group A → line 300');
      final bIdx = out.indexOf('Stroke group B → line 100');
      final cIdx = out.indexOf('Stroke group C → line 200');
      expect(aIdx >= 0 && bIdx > aIdx && cIdx > bIdx, isTrue);
    });
  });

  group('ReviewSerializer — trailing newline', () {
    test('output ends with exactly one LF', () {
      final clock = FakeClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: clock);

      final out = serializer.buildReviewMd(
        job: _job('spec-nl'),
        source: _md(sha: 'abc'),
        questions: const [],
        answers: const {},
        freeFormNotes: '',
        strokeGroups: const [],
      );

      expect(out.endsWith('\n') && !out.endsWith('\n\n'), isTrue);
    });
  });

  group('ReviewSerializer — clock invocation count', () {
    test('Clock.now() is called exactly once per buildReviewMd call', () {
      final spy = _SpyingClock(DateTime(2026, 4, 20, 9, 32));
      final serializer = ReviewSerializer(clock: spy);

      serializer.buildReviewMd(
        job: _job('spec-spy'),
        source: _md(sha: 'abc'),
        questions: const [
          OpenQuestion(id: 'Q1', body: 'x'),
          OpenQuestion(id: 'Q2', body: 'y'),
        ],
        answers: const {'Q1': 'a', 'Q2': 'b'},
        freeFormNotes: 'notes',
        strokeGroups: [_mdGroup(line: 1, ts: '2026-04-20T09:00:00Z')],
      );

      expect(spy.nowCalls, 1);
    });
  });
}

/// Minimal spying [Clock] that counts calls to [now]. Used to verify the
/// serializer does not redundantly poll the clock (IMPLEMENTATION.md §2.3
/// — deterministic domain services).
class _SpyingClock implements Clock {
  _SpyingClock(this._t);

  final DateTime _t;
  int nowCalls = 0;

  @override
  DateTime now() {
    nowCalls++;
    return _t;
  }
}
