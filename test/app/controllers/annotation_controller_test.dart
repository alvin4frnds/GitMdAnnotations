import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/ink_tool.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';

final _jobA = JobRef(
  repo: const RepoRef(owner: 'acme', name: 'widgets'),
  jobId: 'spec-a',
);

final _jobB = JobRef(
  repo: const RepoRef(owner: 'acme', name: 'widgets'),
  jobId: 'spec-b',
);

final _t0 = DateTime.utc(2026, 4, 20, 9, 14, 22);

MarkdownAnchor _anchor() =>
    MarkdownAnchor(lineNumber: 47, sourceSha: 'abc123');

PointerSample _stylus(
  double x,
  double y, {
  double pressure = 0.5,
  DateTime? ts,
}) =>
    PointerSample(
      x: x,
      y: y,
      pressure: pressure,
      kind: PointerKind.stylus,
      timestamp: ts ?? _t0,
    );

PointerSample _touch(double x, double y) => PointerSample(
      x: x,
      y: y,
      pressure: 0.5,
      kind: PointerKind.touch,
      timestamp: _t0,
    );

ProviderContainer _buildContainer({
  FakeClock? clock,
  FakeIdGenerator? idGen,
}) {
  final container = ProviderContainer(overrides: [
    clockProvider.overrideWithValue(clock ?? FakeClock(_t0)),
    idGeneratorProvider.overrideWithValue(idGen ?? FakeIdGenerator()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AnnotationController.build()', () {
    test('initial state: zero groups, no active stroke, tool=pen', () {
      final container = _buildContainer();
      final state = container.read(annotationControllerProvider(_jobA));
      expect(state.groups, isEmpty);
      expect(state.hasActiveStroke, isFalse);
      expect(state.tool, InkTool.pen);
    });

    test('read returns synchronously without throwing', () {
      final container = _buildContainer();
      expect(
        () => container.read(annotationControllerProvider(_jobA)),
        returnsNormally,
      );
    });
  });

  group('AnnotationController stroke intents', () {
    test('beginStroke + endStroke with stylus commits one group', () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      c.endStroke(_stylus(11, 21));
      final state = container.read(annotationControllerProvider(_jobA));
      expect(state.groups, hasLength(1));
      expect(state.hasActiveStroke, isFalse);
    });

    test('beginStroke with touch is a no-op (palm rejection)', () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_touch(10, 20), anchor: _anchor());
      final state = container.read(annotationControllerProvider(_jobA));
      expect(state.hasActiveStroke, isFalse);
      expect(state.groups, isEmpty);
    });

    test('palm mix mid-stroke: touch extend does not contaminate stroke',
        () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      c.extendStroke(_touch(999, 999)); // ignored
      c.extendStroke(_stylus(15, 25));
      c.endStroke(_stylus(20, 30));
      final state = container.read(annotationControllerProvider(_jobA));
      final points = state.groups.single.strokes.single.points;
      final xs = points.map((p) => p.x).toList();
      expect(xs, isNot(contains(999.0)));
      expect(xs, containsAll(<double>[10.0, 15.0, 20.0]));
    });

    test('extendStroke emits state so hasActiveStroke flips to true', () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      final state = container.read(annotationControllerProvider(_jobA));
      expect(state.hasActiveStroke, isTrue);
    });
  });

  group('AnnotationController undo/redo', () {
    test('commit → undo → redo round-trips to the same length', () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      c.endStroke(_stylus(11, 21));
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        hasLength(1),
      );
      c.undo();
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        isEmpty,
      );
      c.redo();
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        hasLength(1),
      );
    });
  });

  group('AnnotationController.setTool', () {
    test('setTool updates state.tool', () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.setTool(InkTool.highlighter);
      expect(
        container.read(annotationControllerProvider(_jobA)).tool,
        InkTool.highlighter,
      );
    });

    test('tool change does not block committing strokes (degrades to pen)',
        () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.setTool(InkTool.arrow);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      c.endStroke(_stylus(11, 21));
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        hasLength(1),
      );
    });
  });

  group('AnnotationController family scoping', () {
    test('two jobs have independent state', () {
      final container = _buildContainer();
      final a = container.read(annotationControllerProvider(_jobA).notifier);
      a.beginStroke(_stylus(10, 20), anchor: _anchor());
      a.endStroke(_stylus(11, 21));
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        hasLength(1),
      );
      expect(
        container.read(annotationControllerProvider(_jobB)).groups,
        isEmpty,
      );
    });
  });

  group('AnnotationController rebuild semantics', () {
    // ProviderContainer tests pin the *rebuild* semantics here: after
    // `container.invalidate(...)`, a subsequent read builds a fresh
    // session, so state is empty again. True route-pop autoDispose is a
    // widget-test concern — family + autoDispose is what lets Riverpod
    // drop the notifier when no watchers remain.
    test('invalidate drops the session and a fresh one is built on next read',
        () {
      final container = _buildContainer();
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      c.endStroke(_stylus(11, 21));
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        hasLength(1),
      );
      container.invalidate(annotationControllerProvider(_jobA));
      expect(
        container.read(annotationControllerProvider(_jobA)).groups,
        isEmpty,
      );
    });
  });

  group('AnnotationController honors overridden ports', () {
    test('commits carry FakeIdGenerator prefix and FakeClock timestamp', () {
      final clock = FakeClock(_t0);
      final container = _buildContainer(clock: clock);
      final c = container.read(annotationControllerProvider(_jobA).notifier);
      c.beginStroke(_stylus(10, 20), anchor: _anchor());
      // Advance the clock after begin; the committed timestamp is captured
      // at begin, not at end (AnnotationSession rule 4).
      clock.advance(const Duration(seconds: 5));
      c.endStroke(_stylus(11, 21));
      final group =
          container.read(annotationControllerProvider(_jobA)).groups.single;
      expect(group.id, 'stroke-group-A');
      expect(group.timestamp, _t0);
    });
  });
}
