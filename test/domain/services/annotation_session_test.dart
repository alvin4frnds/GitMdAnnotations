import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/ink_tool.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/domain/services/annotation_session.dart';

import '_annotation_session_fixtures.dart';

/// Stroke-input contract for [AnnotationSession] — the palm-rejection,
/// commit-on-endStroke, tool-color, sparse-stroke, snapshot-immutability,
/// per-stroke-anchor, and pressure-passthrough rules (T3 rules 1, 2, 3,
/// 4, 7, 8, 9). History rules (undo/redo, tool-change mid-stroke, clock)
/// live in the sibling `annotation_session_history_test.dart` per the
/// §2.6 split-by-responsibility rule.
void main() {
  // Rule 1 — Palm rejection ---------------------------------------------
  group('Rule 1 — Palm rejection', () {
    test('beginStroke with PointerKind.touch is a silent no-op', () {
      final s = newSession();
      s.beginStroke(kindSample(PointerKind.touch), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('beginStroke with PointerKind.mouse is a silent no-op', () {
      final s = newSession();
      s.beginStroke(kindSample(PointerKind.mouse), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('beginStroke with PointerKind.trackpad is a silent no-op', () {
      final s = newSession();
      s.beginStroke(kindSample(PointerKind.trackpad), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('beginStroke with PointerKind.invertedStylus is a silent no-op '
        '(eraser mode reserved for future T4/T5)', () {
      final s = newSession();
      s.beginStroke(
        kindSample(PointerKind.invertedStylus),
        anchor: markdownAnchor,
      );
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('beginStroke with PointerKind.unknown is a silent no-op', () {
      final s = newSession();
      s.beginStroke(kindSample(PointerKind.unknown), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('beginStroke with PointerKind.stylus activates a stroke', () {
      final s = newSession();
      s.beginStroke(stylusSample(10, 20), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isTrue);
    });

    test('extendStroke after a touch-suppressed begin is a no-op', () {
      final s = newSession();
      s.beginStroke(kindSample(PointerKind.touch), anchor: markdownAnchor);
      s.extendStroke(kindSample(PointerKind.touch));
      expect(s.hasActiveStroke, isFalse);
      expect(s.snapshot(), isEmpty);
    });

    test('endStroke while idle is a no-op (stray up-event)', () {
      final s = newSession();
      s.endStroke(stylusSample(0, 0));
      expect(s.snapshot(), isEmpty);
      expect(s.hasActiveStroke, isFalse);
    });

    test(
        'extendStroke with touch sample during active stylus stroke is '
        'rejected (the touch coordinates do not land in the committed stroke)',
        () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.extendStroke(stylusSample(10, 10));
      // Palm lands on the canvas mid-stroke. Must be ignored.
      s.extendStroke(kindSample(PointerKind.touch));
      s.extendStroke(stylusSample(20, 20));
      s.endStroke(stylusSample(30, 30));
      final pts = s.snapshot().single.strokes.single.points;
      expect(pts.map((p) => p.x).toList(), [0, 10, 20, 30]);
      expect(pts.map((p) => p.y).toList(), [0, 10, 20, 30]);
      // The default kindSample coords are (0, 0); if the guard regressed
      // the point list would not have length 4 with these exact x's — but
      // pin the palm coords explicitly too by using a non-origin touch:
      // (the assertion above is already sufficient since a (0,0) touch
      // would have been appended at index 2, shifting (20,20) to index 3
      // and adding a 5th point).
      expect(pts, hasLength(4));
    });

    test(
        'endStroke with touch sample while stylus stroke is active is a '
        'no-op on the end-sample (the stylus extend point is preserved '
        'and the touch coords do not appear)', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.extendStroke(stylusSample(10, 10));
      // A palm-up event arrives while the stylus is still down. The
      // stroke must commit *without* the touch sample's coords.
      s.endStroke(kindSample(PointerKind.touch));
      // The stroke commits on any endStroke call (active != null), but
      // the non-stylus sample is dropped rather than appended.
      expect(s.hasActiveStroke, isFalse);
      final pts = s.snapshot().single.strokes.single.points;
      expect(pts.map((p) => p.x).toList(), [0, 10]);
      expect(pts.map((p) => p.y).toList(), [0, 10]);
      expect(pts, hasLength(2));
    });
  });

  // Rule 2 — Commit on endStroke ----------------------------------------
  group('Rule 2 — Commit-on-endStroke', () {
    test('beginStroke → endStroke commits exactly one StrokeGroup', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      expect(s.snapshot(), hasLength(1));
    });

    test('committed group carries id from idGenerator.next()', () {
      final s = newSession(gen: FakeIdGenerator());
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      expect(s.snapshot().single.id, 'stroke-group-A');
    });

    test('second committed group pulls the next id', () {
      final s = newSession(gen: FakeIdGenerator());
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      s.beginStroke(stylusSample(2, 2), anchor: markdownAnchor);
      s.endStroke(stylusSample(3, 3));
      expect(s.snapshot().map((g) => g.id).toList(),
          ['stroke-group-A', 'stroke-group-B']);
    });

    test('committed group has exactly one Stroke', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.extendStroke(stylusSample(1, 1));
      s.extendStroke(stylusSample(2, 2));
      s.endStroke(stylusSample(3, 3));
      expect(s.snapshot().single.strokes, hasLength(1));
    });

    test('hasActiveStroke is false after endStroke', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      expect(s.hasActiveStroke, isTrue);
      s.endStroke(stylusSample(1, 1));
      expect(s.hasActiveStroke, isFalse);
    });

    test('begin while already active discards the in-progress stroke '
        'and starts fresh (recovery path)', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.extendStroke(stylusSample(1, 1));
      // User's pointer-up was dropped; a new pointer-down arrives.
      s.beginStroke(stylusSample(100, 100), anchor: markdownAnchor);
      s.endStroke(stylusSample(200, 200));
      // Only the fresh stroke is committed; the abandoned one is gone.
      expect(s.snapshot(), hasLength(1));
      final pts = s.snapshot().single.strokes.single.points;
      expect(pts.first.x, 100);
      expect(pts.last.x, 200);
    });
  });

  // Rule 3 — Tool color + width defaults --------------------------------
  group('Rule 3 — Tool color/width defaults', () {
    test('pen produces color #111111 at stroke-width 2.0', () {
      final s = newSession(tool: InkTool.pen);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      final stroke = s.snapshot().single.strokes.single;
      expect(stroke.color, '#111111');
      expect(stroke.strokeWidth, 2.0);
    });

    test('non-pen tools degrade to the same freehand color/width in T3',
        () {
      for (final tool in [
        InkTool.highlighter,
        InkTool.line,
        InkTool.arrow,
        InkTool.rect,
        InkTool.circle,
        InkTool.eraser,
      ]) {
        final s = newSession(tool: tool);
        s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
        s.endStroke(stylusSample(1, 1));
        final stroke = s.snapshot().single.strokes.single;
        expect(stroke.color, '#111111', reason: 'tool: $tool');
        expect(stroke.strokeWidth, 2.0, reason: 'tool: $tool');
      }
    });

    test('non-pen tool still produces exactly one freehand Stroke', () {
      final s = newSession(tool: InkTool.rect);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.extendStroke(stylusSample(5, 5));
      s.extendStroke(stylusSample(10, 10));
      s.endStroke(stylusSample(15, 15));
      expect(s.snapshot().single.strokes, hasLength(1));
      // Points preserved in order — it's a polyline, not a rectangle.
      final xs = s.snapshot().single.strokes.single.points
          .map((p) => p.x)
          .toList();
      expect(xs, [0, 5, 10, 15]);
    });
  });

  // Rule 4 — Sparse strokes commit ---------------------------------------
  group('Rule 4 — Sparse strokes', () {
    test('begin → end with no extends commits a two-point stroke '
        '(begin + end samples)', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(10, 10));
      expect(s.snapshot().single.strokes.single.points, hasLength(2));
    });

    test('begin → end at the same coord commits a (possibly degenerate) '
        'stroke that still has 2 points (matches T2 single-point golden)',
        () {
      final s = newSession();
      s.beginStroke(stylusSample(5, 5), anchor: markdownAnchor);
      s.endStroke(stylusSample(5, 5));
      final pts = s.snapshot().single.strokes.single.points;
      expect(pts, hasLength(2));
      expect(pts.first.x, 5);
      expect(pts.last.x, 5);
    });
  });

  // Rule 7 — Snapshot immutability --------------------------------------
  group('Rule 7 — Snapshot is a defensive copy', () {
    test('mutating the returned list does not affect the session', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      final snap = s.snapshot();
      snap.clear();
      expect(s.snapshot(), hasLength(1));
    });
  });

  // Rule 8 — Per-stroke anchor ------------------------------------------
  group('Rule 8 — Per-stroke anchor', () {
    test('two strokes at different anchors retain their own anchor', () {
      final a = MarkdownAnchor(lineNumber: 10, sourceSha: 'sha1');
      final b = MarkdownAnchor(lineNumber: 42, sourceSha: 'sha1');
      final s = newSession(initial: a);
      s.beginStroke(stylusSample(0, 0), anchor: a);
      s.endStroke(stylusSample(1, 1));
      s.beginStroke(stylusSample(2, 2), anchor: b);
      s.endStroke(stylusSample(3, 3));
      final groups = s.snapshot();
      expect(groups[0].anchor, a);
      expect(groups[1].anchor, b);
    });
  });

  // Rule 9 — Pressure passthrough ---------------------------------------
  group('Rule 9 — Pressure passthrough', () {
    test('three extends with pressures 0.1/0.5/0.9 survive into the '
        'committed group', () {
      final s = newSession();
      s.beginStroke(stylusSample(0, 0, pressure: 0.1),
          anchor: markdownAnchor);
      s.extendStroke(stylusSample(1, 1, pressure: 0.5));
      s.extendStroke(stylusSample(2, 2, pressure: 0.9));
      s.endStroke(stylusSample(3, 3, pressure: 0.5));
      final pts = s.snapshot().single.strokes.single.points;
      expect(pts.map((p) => p.pressure).toList(), [0.1, 0.5, 0.9, 0.5]);
    });
  });

  // Constructor validation ---------------------------------------------
  group('AnnotationSession constructor — undoDepth validation', () {
    test('throws ArgumentError when undoDepth == 0 '
        '(0 has no recoverable state)', () {
      expect(
        () => AnnotationSession(
          initialAnchor: markdownAnchor,
          tool: InkTool.pen,
          clock: FakeClock(baseInstant),
          idGenerator: FakeIdGenerator(),
          undoDepth: 0,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when undoDepth < 0 (negative is nonsense)',
        () {
      expect(
        () => AnnotationSession(
          initialAnchor: markdownAnchor,
          tool: InkTool.pen,
          clock: FakeClock(baseInstant),
          idGenerator: FakeIdGenerator(),
          undoDepth: -1,
        ),
        throwsArgumentError,
      );
    });
  });
}
