import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/review_controller.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/review_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/spec_providers.dart';
import 'package:gitmdannotations_tablet/app/providers/sync_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/source_kind.dart';
import 'package:gitmdannotations_tablet/domain/entities/spec_file.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_git_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_png_flattener.dart';
import 'package:gitmdannotations_tablet/domain/services/open_question_extractor.dart';

final _repo = const RepoRef(owner: 'acme', name: 'widgets');
final _jobA = JobRef(repo: _repo, jobId: 'spec-a');
const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
final _t0 = DateTime.utc(2026, 4, 20, 9, 14, 22);

SpecFile _specMd({String contents = '# S\n\n## Open questions\n\n### Q1: Why?\n'}) =>
    SpecFile(
      path: 'jobs/pending/spec-a/02-spec.md',
      sha: 'abc123',
      contents: contents,
      sourceKind: SourceKind.markdown,
    );

List<OpenQuestion> _questions() =>
    const [OpenQuestion(id: 'Q1', body: 'Why?')];

StrokeGroup _group() => StrokeGroup(
      id: 'stroke-group-A',
      anchor: MarkdownAnchor(lineNumber: 3, sourceSha: 'abc123'),
      timestamp: _t0,
      strokes: [
        Stroke(
          color: '#ff0000',
          strokeWidth: 2,
          points: [
            StrokePoint(x: 1, y: 2, pressure: 0.5),
            StrokePoint(x: 3, y: 4, pressure: 0.5),
          ],
        ),
      ],
    );

class _Env {
  _Env({
    required this.container,
    required this.fs,
    required this.git,
    required this.clock,
    required this.png,
  });

  final ProviderContainer container;
  final FakeFileSystem fs;
  final FakeGitPort git;
  final FakeClock clock;
  final FakePngFlattener png;
}

_Env _buildEnv({
  FakeFileSystem? fs,
  FakeGitPort? git,
  FakeClock? clock,
  FakePngFlattener? png,
}) {
  final fs0 = fs ?? FakeFileSystem();
  final git0 = git ?? FakeGitPort(initial: {'claude-jobs': <String, String>{}});
  final clock0 = clock ?? FakeClock(_t0);
  final png0 = png ?? FakePngFlattener();
  final container = ProviderContainer(overrides: [
    fileSystemProvider.overrideWithValue(fs0),
    gitPortProvider.overrideWithValue(git0),
    clockProvider.overrideWithValue(clock0),
    idGeneratorProvider.overrideWithValue(FakeIdGenerator()),
    pngFlattenerProvider.overrideWithValue(png0),
  ]);
  addTearDown(container.dispose);
  return _Env(
    container: container,
    fs: fs0,
    git: git0,
    clock: clock0,
    png: png0,
  );
}

void main() {
  group('ReviewController.build()', () {
    test('fresh JobRef with no draft yields empty state + idle submission',
        () async {
      final env = _buildEnv();
      final state =
          await env.container.read(reviewControllerProvider(_jobA).future);
      expect(state.answers, isEmpty);
      expect(state.freeFormNotes, isEmpty);
      expect(state.lastAutoSaveAt, isNull);
      expect(state.submission, isA<ReviewSubmissionIdle>());
    });

    test('resumes answers + notes from an on-disk draft', () async {
      final fs = FakeFileSystem();
      fs.seedFile(
        '/docs/drafts/spec-a/03-review.md.draft',
        jsonEncode({
          'answers': {'Q1': 'because reasons'},
          'freeFormNotes': 'needs more work',
        }),
      );
      final env = _buildEnv(fs: fs);
      final state =
          await env.container.read(reviewControllerProvider(_jobA).future);
      expect(state.answers['Q1'], 'because reasons');
      expect(state.freeFormNotes, 'needs more work');
    });

    test('corrupt draft is ignored — state remains empty', () async {
      final fs = FakeFileSystem();
      fs.seedFile(
        '/docs/drafts/spec-a/03-review.md.draft',
        '{not valid json',
      );
      final env = _buildEnv(fs: fs);
      final state =
          await env.container.read(reviewControllerProvider(_jobA).future);
      expect(state.answers, isEmpty);
    });
  });

  group('ReviewController intents', () {
    test('setAnswer updates answers map without touching notes', () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);
      notifier.setAnswer('Q1', 'hello');
      final state = env.container.read(reviewControllerProvider(_jobA)).value!;
      expect(state.answers, {'Q1': 'hello'});
    });

    test('setFreeFormNotes replaces the notes body', () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);
      notifier.setFreeFormNotes('zap');
      final state = env.container.read(reviewControllerProvider(_jobA)).value!;
      expect(state.freeFormNotes, 'zap');
    });
  });

  group('ReviewController auto-save', () {
    test('setAnswer persists the draft and stamps lastAutoSaveAt from the clock',
        () async {
      final env = _buildEnv();
      // Keep an active subscription so autoDispose doesn't drop the
      // notifier between the `read(.future)` await and the post-save
      // assertion below.
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);

      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'draft answer');
      // Let the scheduled save microtask run + state propagation settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final draft =
          await env.fs.readString('/docs/drafts/spec-a/03-review.md.draft');
      final decoded = jsonDecode(draft) as Map<String, dynamic>;
      expect(decoded['answers'], {'Q1': 'draft answer'});
      final async = env.container.read(reviewControllerProvider(_jobA));
      expect(async.value?.lastAutoSaveAt, _t0);
    });
  });

  group('ReviewController.submit', () {
    test('happy path composes review.md, changelog, and commits atomically',
        () async {
      final specContents = '# Spec\n\n## Open questions\n\n### Q1: Why?\n';
      final env = _buildEnv(
        png: FakePngFlattener(output: Uint8List.fromList([1, 2, 3])),
      );
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);
      notifier.setAnswer('Q1', 'because reasons');

      await notifier.submit(
        source: _specMd(contents: specContents),
        questions: _questions(),
        strokeGroups: [_group()],
        identity: _identity,
      );

      final state = env.container.read(reviewControllerProvider(_jobA)).value!;
      expect(state.submission, isA<ReviewSubmissionSuccess>());
      final tree = env.git.branches['claude-jobs']!;
      expect(tree.containsKey('jobs/pending/spec-a/03-review.md'), isTrue);
      expect(
          env.git.binaryBranches['claude-jobs']![
              'jobs/pending/spec-a/03-annotations.png'],
          Uint8List.fromList([1, 2, 3]));
    });

    test('deletes the draft after a successful submit', () async {
      final fs = FakeFileSystem();
      fs.seedFile(
        '/docs/drafts/spec-a/03-review.md.draft',
        jsonEncode({
          'answers': {'Q1': 'x'},
          'freeFormNotes': '',
        }),
      );
      final env = _buildEnv(fs: fs);
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      await notifier.submit(
        source: _specMd(),
        questions: _questions(),
        strokeGroups: [_group()],
        identity: _identity,
      );

      expect(
        await env.fs.exists('/docs/drafts/spec-a/03-review.md.draft'),
        isFalse,
      );
    });

    test('submission failure transitions to ReviewSubmissionFailure',
        () async {
      // Stroke group anchored to a different sha than the spec triggers a
      // typed CommitPlannerAnchorShaMismatch downstream.
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      final badGroup = StrokeGroup(
        id: 'bad',
        anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'OTHER'),
        timestamp: _t0,
        strokes: [
          Stroke(
            color: '#ff0000',
            strokeWidth: 2,
            points: [StrokePoint(x: 0, y: 0, pressure: 0.5)],
          ),
        ],
      );

      await notifier.submit(
        source: _specMd(),
        questions: _questions(),
        strokeGroups: [badGroup],
        identity: _identity,
      );

      final state = env.container.read(reviewControllerProvider(_jobA)).value!;
      expect(state.submission, isA<ReviewSubmissionFailure>());
    });
  });

  group('ReviewController.approve', () {
    test('approve composes changelog + 05-approved and commits', () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      await notifier.approve(
        source: _specMd(),
        identity: _identity,
      );

      final tree = env.git.branches['claude-jobs']!;
      expect(tree.containsKey('jobs/pending/spec-a/05-approved'), isTrue);
    });
  });
}
