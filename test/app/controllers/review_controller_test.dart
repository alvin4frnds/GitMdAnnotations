import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/review_controller.dart';
import 'package:gitmdscribe/app/providers/annotation_providers.dart';
import 'package:gitmdscribe/app/providers/review_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/app/providers/sync_providers.dart';
import 'package:gitmdscribe/domain/entities/anchor.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/entities/job_ref.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/entities/source_kind.dart';
import 'package:gitmdscribe/domain/entities/spec_file.dart';
import 'package:gitmdscribe/domain/entities/stroke.dart';
import 'package:gitmdscribe/domain/entities/stroke_group.dart';
import 'package:gitmdscribe/domain/fakes/fake_clock.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/ports/file_system_port.dart';
import 'package:gitmdscribe/domain/fakes/fake_git_port.dart';
import 'package:gitmdscribe/domain/fakes/fake_id_generator.dart';
import 'package:gitmdscribe/domain/fakes/fake_markdown_rasterizer.dart';
import 'package:gitmdscribe/domain/fakes/fake_png_flattener.dart';
import 'package:gitmdscribe/domain/services/open_question_extractor.dart';

/// Manual periodic-timer driver used by the auto-save tests. Captures the
/// callback that [ReviewController.build] registers so tests can call
/// [fire] to advance one tick without waiting on real time.
class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function(Timer) callback;
  bool _cancelled = false;
  int _ticks = 0;

  void fire() {
    if (_cancelled) return;
    _ticks++;
    callback(this);
  }

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _ticks;
}

class _TimerSeam {
  _FakeTimer? timer;
  Timer spawn(Duration _, void Function(Timer) cb) {
    final t = _FakeTimer(cb);
    timer = t;
    return t;
  }
}

/// [FakeFileSystem] wrapper that blocks [writeString] until an external
/// [Completer] fires. Used to simulate a slow disk write so tests can
/// verify the in-flight-skip guard in [ReviewController._maybePersist].
class _GatedFileSystem implements FileSystemPort {
  _GatedFileSystem({required this.gate});
  final Completer<void> gate;
  final FakeFileSystem _inner = FakeFileSystem();
  int writeCount = 0;

  @override
  Future<void> writeString(String path, String contents) async {
    writeCount++;
    await gate.future;
    await _inner.writeString(path, contents);
  }

  @override
  Future<bool> exists(String path) => _inner.exists(path);
  @override
  Future<List<FsEntry>> listDir(String dir) => _inner.listDir(dir);
  @override
  Future<String> readString(String path) => _inner.readString(path);
  @override
  Future<List<int>> readBytes(String path) => _inner.readBytes(path);
  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _inner.writeBytes(path, bytes);
  @override
  Future<void> mkdirp(String path) => _inner.mkdirp(path);
  @override
  Future<void> remove(String path) => _inner.remove(path);
  @override
  Future<String> appDocsPath(String sub) => _inner.appDocsPath(sub);
}

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
    required this.timerSeam,
  });

  final ProviderContainer container;
  final FileSystemPort fs;
  final FakeGitPort git;
  final FakeClock clock;
  final FakePngFlattener png;
  final _TimerSeam timerSeam;
}

_Env _buildEnv({
  FileSystemPort? fs,
  FakeGitPort? git,
  FakeClock? clock,
  FakePngFlattener? png,
  List<Override> extraOverrides = const [],
}) {
  final fs0 = fs ?? FakeFileSystem();
  final git0 = git ?? FakeGitPort(initial: {'claude-jobs': <String, String>{}});
  final clock0 = clock ?? FakeClock(_t0);
  final png0 = png ?? FakePngFlattener();
  final seam = _TimerSeam();
  final container = ProviderContainer(overrides: [
    fileSystemProvider.overrideWithValue(fs0),
    gitPortProvider.overrideWithValue(git0),
    clockProvider.overrideWithValue(clock0),
    idGeneratorProvider.overrideWithValue(FakeIdGenerator()),
    pngFlattenerProvider.overrideWithValue(png0),
    markdownRasterizerProvider.overrideWithValue(FakeMarkdownRasterizer()),
    reviewAutoSaveTimerFactoryProvider.overrideWithValue(seam.spawn),
    ...extraOverrides,
  ]);
  addTearDown(container.dispose);
  return _Env(
    container: container,
    fs: fs0,
    git: git0,
    clock: clock0,
    png: png0,
    timerSeam: seam,
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
    test('timer tick persists the draft and stamps lastAutoSaveAt from the clock',
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
      // No microtask-save path now — the draft must not be on disk yet.
      await Future<void>.delayed(Duration.zero);
      expect(
        await env.fs.exists('/docs/drafts/spec-a/03-review.md.draft'),
        isFalse,
        reason: 'auto-save should not fire until the timer ticks',
      );

      env.timerSeam.timer!.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final draft =
          await env.fs.readString('/docs/drafts/spec-a/03-review.md.draft');
      final decoded = jsonDecode(draft) as Map<String, dynamic>;
      expect(decoded['answers'], {'Q1': 'draft answer'});
      final async = env.container.read(reviewControllerProvider(_jobA));
      expect(async.value?.lastAutoSaveAt, _t0);
    });

    test('tick is a no-op when the draft is unchanged since the last save',
        () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'v1');
      env.timerSeam.timer!.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Bump the clock so we can detect whether a second save occurred —
      // lastAutoSaveAt would advance if it did.
      final firstSaveAt = env.container
          .read(reviewControllerProvider(_jobA))
          .value!
          .lastAutoSaveAt;
      env.clock.advance(const Duration(seconds: 30));
      env.timerSeam.timer!.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final afterSecondTick = env.container
          .read(reviewControllerProvider(_jobA))
          .value!
          .lastAutoSaveAt;
      expect(afterSecondTick, firstSaveAt,
          reason: 'clean-tick should not restamp lastAutoSaveAt');
    });

    test('multiple keystrokes between ticks coalesce into a single write',
        () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'a');
      notifier.setAnswer('Q1', 'ab');
      notifier.setAnswer('Q1', 'abc');
      env.timerSeam.timer!.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final draft =
          await env.fs.readString('/docs/drafts/spec-a/03-review.md.draft');
      final decoded = jsonDecode(draft) as Map<String, dynamic>;
      expect(decoded['answers'], {'Q1': 'abc'},
          reason: 'tick should write only the latest state');
    });

    test('timer is cancelled on controller dispose', () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      await env.container.read(reviewControllerProvider(_jobA).future);
      final timer = env.timerSeam.timer!;
      expect(timer.isActive, isTrue);

      sub.close();
      // autoDispose only fires after the microtask queue drains the
      // listener-release signal.
      await Future<void>.delayed(Duration.zero);

      expect(timer.isActive, isFalse);
    });

    test('pop-save flushes dirty edits on dispose before the next tick',
        () async {
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'unsaved edit');
      // Screen pops before the timer fires.
      sub.close();
      // Let the dispose microtask + pop-save future settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final draft =
          await env.fs.readString('/docs/drafts/spec-a/03-review.md.draft');
      final decoded = jsonDecode(draft) as Map<String, dynamic>;
      expect(decoded['answers'], {'Q1': 'unsaved edit'});
    });

    test('reopen rehydrates from the persisted draft', () async {
      // End-to-end restore: tick persists → dispose → new subscription
      // on the same jobRef reads back the prior answers.
      final env = _buildEnv();
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'persisted');
      notifier.setFreeFormNotes('notes body');
      env.timerSeam.timer!.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Fresh subscription on the same JobRef — autoDispose spins up a new
      // notifier which must replay the persisted draft.
      final sub2 =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub2.close);
      final restored =
          await env.container.read(reviewControllerProvider(_jobA).future);
      expect(restored.answers, {'Q1': 'persisted'});
      expect(restored.freeFormNotes, 'notes body');
    });

    test('in-flight write is not duplicated by a concurrent tick', () async {
      // A slow draft store blocks the first save; the second tick fires
      // while it's still in flight and must skip rather than stack.
      final gate = Completer<void>();
      final slow = _GatedFileSystem(gate: gate);
      final env = _buildEnv(fs: slow);
      final sub =
          env.container.listen(reviewControllerProvider(_jobA), (_, _) {});
      addTearDown(sub.close);
      final notifier =
          env.container.read(reviewControllerProvider(_jobA).notifier);
      await env.container.read(reviewControllerProvider(_jobA).future);

      notifier.setAnswer('Q1', 'v1');
      env.timerSeam.timer!.fire(); // start persist, blocks on gate
      await Future<void>.delayed(Duration.zero);
      env.timerSeam.timer!.fire(); // second tick while first is in flight
      await Future<void>.delayed(Duration.zero);

      expect(slow.writeCount, 1,
          reason: 'second tick must skip while first is in flight');

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(slow.writeCount, 1,
          reason: 'no retroactive write should fire after the gate opens');
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
