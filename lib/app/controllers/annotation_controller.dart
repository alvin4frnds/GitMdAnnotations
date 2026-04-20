import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/anchor.dart';
import '../../domain/entities/ink_tool.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/pointer_sample.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/services/annotation_session.dart';
import '../providers/annotation_providers.dart';

/// UI-facing state for the annotation canvas. Mirrors the slice of
/// [AnnotationSession] that widgets need to repaint: committed groups, a
/// mid-stroke flag for in-progress rendering, and the current tool.
class AnnotationState {
  const AnnotationState({
    required this.groups,
    required this.hasActiveStroke,
    required this.tool,
  });

  const AnnotationState.initial()
      : groups = const <StrokeGroup>[],
        hasActiveStroke = false,
        tool = InkTool.pen;

  final List<StrokeGroup> groups;
  final bool hasActiveStroke;
  final InkTool tool;

  AnnotationState copyWith({
    List<StrokeGroup>? groups,
    bool? hasActiveStroke,
    InkTool? tool,
  }) =>
      AnnotationState(
        groups: groups ?? this.groups,
        hasActiveStroke: hasActiveStroke ?? this.hasActiveStroke,
        tool: tool ?? this.tool,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnnotationState) return false;
    if (other.hasActiveStroke != hasActiveStroke) return false;
    if (other.tool != tool) return false;
    if (other.groups.length != groups.length) return false;
    for (var i = 0; i < groups.length; i++) {
      if (other.groups[i] != groups[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(groups), hasActiveStroke, tool);

  @override
  String toString() =>
      'AnnotationState(groups: ${groups.length}, active: $hasActiveStroke, tool: $tool)';
}

/// Per-job Riverpod notifier that owns a single [AnnotationSession] and
/// re-emits [AnnotationState] on every mutating intent. Scoped via
/// `NotifierProvider.autoDispose.family` so the session dies with the route
/// (IMPLEMENTATION.md §2.2 — "annotation session state must die when the
/// SpecReader screen pops").
///
/// The raw [AnnotationSession] is deliberately kept private — the controller
/// is the only mutator. T7 will wire this controller into `AnnotationCanvas`.
class AnnotationController
    extends AutoDisposeFamilyNotifier<AnnotationState, JobRef> {
  // Not `final` — Riverpod reuses the notifier instance across rebuilds
  // (e.g. `container.invalidate`), calling [build] again. Assigning here
  // replaces the previous session so invalidation yields a cold state.
  late AnnotationSession _session;

  @override
  AnnotationState build(JobRef arg) {
    final clock = ref.read(clockProvider);
    final ids = ref.read(idGeneratorProvider);
    _session = AnnotationSession(
      // T5 uses a sentinel anchor here; T7 (wiring the canvas) will inject
      // the real anchor (and probably a per-stroke anchor via beginStroke)
      // when pointer events land. The sentinel is harmless because
      // AnnotationSession takes the per-stroke anchor as a beginStroke arg
      // and only stores `initialAnchor` for future reanchor flows.
      initialAnchor: MarkdownAnchor(lineNumber: 1, sourceSha: ''),
      tool: InkTool.pen,
      clock: clock,
      idGenerator: ids,
    );
    return const AnnotationState.initial();
  }

  // -- Intents ---------------------------------------------------------

  void beginStroke(PointerSample sample, {required Anchor anchor}) {
    _session.beginStroke(sample, anchor: anchor);
    _emit();
  }

  void extendStroke(PointerSample sample) {
    _session.extendStroke(sample);
    _emit();
  }

  void endStroke(PointerSample sample) {
    _session.endStroke(sample);
    _emit();
  }

  void undo() {
    _session.undo();
    _emit();
  }

  void redo() {
    _session.redo();
    _emit();
  }

  void setTool(InkTool tool) {
    _session.setTool(tool);
    state = state.copyWith(tool: tool);
  }

  // -- Internals -------------------------------------------------------

  void _emit() {
    state = state.copyWith(
      groups: _session.snapshot(),
      hasActiveStroke: _session.hasActiveStroke,
    );
  }
}
