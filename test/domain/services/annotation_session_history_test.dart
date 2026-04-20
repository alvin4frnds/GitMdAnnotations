import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/ink_tool.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/services/annotation_session.dart';

import '_annotation_session_fixtures.dart';

/// History-side contract for [AnnotationSession]: undo / redo (rule 5),
/// tool-change mid-stroke (rule 6), and timestamp-at-beginStroke (rule
/// 10). Stroke-input concerns live in the sibling
/// `annotation_session_test.dart` file.
void main() {
  void drawOne(AnnotationSession s, {int at = 0}) {
    s.beginStroke(stylusSample(at.toDouble(), 0), anchor: markdownAnchor);
    s.endStroke(stylusSample(at.toDouble() + 1, 1));
  }

  // Rule 5 — Undo / Redo -----------------------------------------------
  group('Rule 5 — Undo/Redo', () {
    test('one stroke = one undo step', () {
      final s = newSession();
      drawOne(s, at: 0);
      expect(s.snapshot(), hasLength(1));
      s.undo();
      expect(s.snapshot(), isEmpty);
    });

    test('undo then redo restores the committed group', () {
      final s = newSession();
      drawOne(s, at: 0);
      s.undo();
      s.redo();
      expect(s.snapshot(), hasLength(1));
    });

    test('starting a new stroke clears the redo stack', () {
      final s = newSession();
      drawOne(s, at: 0);
      s.undo();
      drawOne(s, at: 10); // new interaction clears redo
      s.redo(); // should be a no-op
      expect(s.snapshot(), hasLength(1));
      expect(s.snapshot().single.strokes.single.points.first.x, 10);
    });

    test('undo while a stroke is active is a no-op', () {
      final s = newSession();
      drawOne(s, at: 0);
      s.beginStroke(stylusSample(100, 100), anchor: markdownAnchor);
      s.undo();
      // Active stroke was NOT committed yet; undo did NOT pop the
      // previously committed stroke either.
      s.endStroke(stylusSample(200, 200));
      expect(s.snapshot(), hasLength(2));
    });

    test('redo while a stroke is active is a no-op', () {
      final s = newSession();
      drawOne(s, at: 0);
      s.undo();
      s.beginStroke(stylusSample(50, 50), anchor: markdownAnchor);
      s.redo(); // ignored
      s.endStroke(stylusSample(60, 60));
      // Redo was dropped; the active stroke committed; the redo stack
      // was cleared by starting a new stroke — only one group exists.
      expect(s.snapshot(), hasLength(1));
      expect(s.snapshot().single.strokes.single.points.first.x, 50);
    });

    test('undo when stack is empty is a no-op (does not throw)', () {
      final s = newSession();
      expect(s.undo, returnsNormally);
      expect(s.snapshot(), isEmpty);
    });

    test('redo when stack is empty is a no-op (does not throw)', () {
      final s = newSession();
      expect(s.redo, returnsNormally);
      expect(s.snapshot(), isEmpty);
    });

    test('undoDepth caps the undoable most-recent strokes', () {
      // undoDepth = 3, draw 5 strokes, undo 5 times:
      //   strokes 1 and 2 are beyond the cap and stay in snapshot forever;
      //   strokes 3, 4, 5 undo one at a time; remaining calls no-op.
      final s = newSession(undoDepth: 3);
      for (var i = 0; i < 5; i++) {
        drawOne(s, at: i * 10);
      }
      expect(s.snapshot(), hasLength(5));
      for (var i = 0; i < 5; i++) {
        s.undo();
      }
      expect(s.snapshot(), hasLength(2));
      // Remaining are the oldest two strokes, in order.
      expect(
        s.snapshot().map((g) => g.strokes.single.points.first.x).toList(),
        [0, 10],
      );
    });

    test('default undoDepth is 50 (documented cap from PRD §5.4 FR-1.20)',
        () {
      final s = newSession(); // default undoDepth
      for (var i = 0; i < 60; i++) {
        drawOne(s, at: i);
      }
      for (var i = 0; i < 50; i++) {
        s.undo();
      }
      expect(s.snapshot(), hasLength(10));
      // Further undo is a no-op.
      s.undo();
      expect(s.snapshot(), hasLength(10));
    });
  });

  // Rule 6 — Tool change during active stroke ---------------------------
  group('Rule 6 — Tool-change mid-stroke', () {
    test('setTool during an active stroke does not retroactively recolor '
        'the committed group', () {
      final s = newSession(tool: InkTool.pen);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.setTool(InkTool.highlighter);
      s.endStroke(stylusSample(1, 1));
      // Still the pen default from beginStroke-time.
      expect(s.snapshot().single.strokes.single.color, '#111111');
      expect(s.snapshot().single.strokes.single.strokeWidth, 2.0);
    });

    test('setTool before beginStroke is honored by the next stroke', () {
      final s = newSession(tool: InkTool.pen);
      s.setTool(InkTool.eraser);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      // In T3, non-pen tools still use the pen defaults (documented
      // degradation). This pins the degradation; T4/T5 will change the
      // expectation alongside the real per-tool wiring.
      expect(s.snapshot().single.strokes.single.color, '#111111');
    });
  });

  // Rule 10 — Timestamp at beginStroke, not endStroke -------------------
  group('Rule 10 — Timestamp-at-begin', () {
    test('group.timestamp is clock.now() at beginStroke time, even if '
        'the clock advances before endStroke', () {
      final clock = FakeClock(baseInstant);
      final s = newSession(clock: clock);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      clock.advance(const Duration(seconds: 10));
      s.endStroke(stylusSample(1, 1));
      expect(s.snapshot().single.timestamp, baseInstant);
    });

    test('two strokes drawn at different clock instants record their own '
        'timestamps', () {
      final clock = FakeClock(baseInstant);
      final s = newSession(clock: clock);
      s.beginStroke(stylusSample(0, 0), anchor: markdownAnchor);
      s.endStroke(stylusSample(1, 1));
      clock.advance(const Duration(minutes: 3));
      s.beginStroke(stylusSample(2, 2), anchor: markdownAnchor);
      s.endStroke(stylusSample(3, 3));
      expect(s.snapshot()[0].timestamp, baseInstant);
      expect(
        s.snapshot()[1].timestamp,
        baseInstant.add(const Duration(minutes: 3)),
      );
    });
  });
}
