import '../entities/anchor.dart';
import '../entities/ink_tool.dart';
import '../entities/pointer_sample.dart';
import '../entities/stroke.dart';
import '../entities/stroke_group.dart';
import '../ports/clock_port.dart';
import '../ports/id_generator_port.dart';

/// Pen-stroke state machine for the annotation canvas. Accepts
/// domain-level [PointerSample]s (the UI layer converts Flutter
/// `PointerEvent`s at the boundary — IMPLEMENTATION.md §2.6) and produces
/// an ordered list of committed [StrokeGroup]s plus an undo/redo stack.
///
/// Behavior is pinned by `test/domain/services/annotation_session_test.dart`
/// against rules 1–10 of the T3 brief. See PRD §5.4 and IMPLEMENTATION.md §4.5.
class AnnotationSession {
  AnnotationSession({
    required Anchor initialAnchor,
    required InkTool tool,
    required Clock clock,
    required IdGenerator idGenerator,
    this.undoDepth = 50,
    this.allowedPointerKinds = const {PointerKind.stylus},
  })  : _tool = tool,
        _clock = clock,
        _ids = idGenerator,
        _initialAnchor = initialAnchor {
    if (undoDepth < 1) {
      throw ArgumentError.value(undoDepth, 'undoDepth', 'must be >= 1');
    }
    if (allowedPointerKinds.isEmpty) {
      throw ArgumentError.value(
        allowedPointerKinds,
        'allowedPointerKinds',
        'must contain at least one kind',
      );
    }
  }

  /// Pointer kinds that are allowed to drive strokes. Defaults to
  /// `{PointerKind.stylus}` — palm rejection per PRD §5.4 FR-1.16/FR-1.17.
  /// Desktop/emulator dev loops can widen this set via bootstrap so mouse
  /// events exercise the annotation canvas; production tablet builds keep
  /// the default.
  final Set<PointerKind> allowedPointerKinds;

  /// Maximum number of most-recent strokes that can be undone. Strokes
  /// drawn earlier than the cap remain in [snapshot] but cannot be popped
  /// back. Defaults to 50 per PRD §5.4 FR-1.20.
  final int undoDepth;

  // Unused today (future: reanchor empty-session behavior), kept to match
  // the documented ctor signature and future reset-on-new-job flows.
  // ignore: unused_field
  final Anchor _initialAnchor;

  InkTool _tool;
  final Clock _clock;
  final IdGenerator _ids;

  /// Committed groups in draw order. Includes groups that have aged out
  /// past [undoDepth] and are therefore no longer undoable.
  final List<StrokeGroup> _committed = [];

  /// LIFO stack of undoable groups. Kept in sync with the tail of
  /// [_committed]; bounded to [undoDepth].
  final List<StrokeGroup> _undoStack = [];

  /// LIFO stack of previously undone groups, ready to be redone.
  final List<StrokeGroup> _redoStack = [];

  /// In-progress stroke state. Null when idle.
  _ActiveStroke? _active;

  bool get hasActiveStroke => _active != null;

  // -- Stroke input ----------------------------------------------------

  void beginStroke(PointerSample sample, {required Anchor anchor}) {
    if (!allowedPointerKinds.contains(sample.kind)) {
      // Palm rejection (rule 1). Silent no-op.
      return;
    }
    // Recovery path (rule 2): if a stroke is already active, discard it
    // and start fresh. The in-progress samples are dropped, not committed.
    _active = _ActiveStroke(
      anchor: anchor,
      tool: _tool,
      startedAt: _clock.now(),
      points: [_pointFrom(sample)],
    );
  }

  void extendStroke(PointerSample sample) {
    final active = _active;
    if (active == null) return; // idle — drop stray move event
    if (!allowedPointerKinds.contains(sample.kind)) return;
    active.points.add(_pointFrom(sample));
  }

  void endStroke(PointerSample sample) {
    final active = _active;
    if (active == null) return; // idle — drop stray up event
    if (allowedPointerKinds.contains(sample.kind)) {
      active.points.add(_pointFrom(sample));
    }
    _commit(active);
    _active = null;
  }

  // -- History ---------------------------------------------------------

  void undo() {
    if (_active != null) return; // ignore mid-stroke
    if (_undoStack.isEmpty) return;
    final g = _undoStack.removeLast();
    _committed.remove(g);
    _redoStack.add(g);
  }

  void redo() {
    if (_active != null) return; // ignore mid-stroke
    if (_redoStack.isEmpty) return;
    final g = _redoStack.removeLast();
    _committed.add(g);
    _pushUndo(g);
  }

  // -- Tool + color + snapshot ----------------------------------------

  void setTool(InkTool t) {
    _tool = t;
  }

  /// Hex string (`#RRGGBB`, 7 chars) used for every new stroke. Defaults
  /// to the "near-black" pen color to preserve the M1b-T3 behavior. The
  /// UI palette (PRD §5.4 FR-1.18) dispatches through [setColor].
  String get color => _color;

  /// Update the active ink color. Hex format (`#RRGGBB`). Silently
  /// accepts any 7-char `#...` string — the UI enforces the 5-preset
  /// palette, the domain just stores + echoes it into every subsequent
  /// [Stroke].
  void setColor(String hex) {
    _color = hex;
  }

  String _color = '#111111';

  /// Returns a fresh mutable copy. Callers can mutate the returned list
  /// without affecting the session — rule 7.
  List<StrokeGroup> snapshot() => List<StrokeGroup>.of(_committed);

  // -- Internals -------------------------------------------------------

  void _commit(_ActiveStroke a) {
    final stroke = Stroke(
      points: List<StrokePoint>.unmodifiable(a.points),
      color: _colorFor(a.tool),
      strokeWidth: _widthFor(a.tool),
    );
    final group = StrokeGroup(
      id: _ids.next(),
      anchor: a.anchor,
      timestamp: a.startedAt,
      strokes: [stroke],
    );
    _committed.add(group);
    _pushUndo(group);
    _redoStack.clear(); // new stroke drops the redo history (rule 5)
  }

  void _pushUndo(StrokeGroup g) {
    _undoStack.add(g);
    if (_undoStack.length > undoDepth) {
      _undoStack.removeAt(0); // oldest beyond cap ages out
    }
  }

  StrokePoint _pointFrom(PointerSample s) =>
      StrokePoint(x: s.x, y: s.y, pressure: s.pressure);

  // Tool-specific color mapping was deferred from T3; current design is
  // tool-agnostic ink with a user-selected palette color. Width is still
  // pen-fixed; revisit if tool differentiation ships later.
  String _colorFor(InkTool _) => _color;
  double _widthFor(InkTool _) => 2.0;
}

class _ActiveStroke {
  _ActiveStroke({
    required this.anchor,
    required this.tool,
    required this.startedAt,
    required this.points,
  });

  final Anchor anchor;
  final InkTool tool;
  final DateTime startedAt;
  final List<StrokePoint> points;
}
