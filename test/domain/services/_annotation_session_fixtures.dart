import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/ink_tool.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/domain/services/annotation_session.dart';

/// Shared fixtures for [AnnotationSession] tests. Kept private (leading
/// underscore in the filename would hide from pub, but we use a shared
/// dart file in test/ — underscore-prefix convention only to signal
/// "not a standalone test suite").
final markdownAnchor = MarkdownAnchor(lineNumber: 47, sourceSha: 'abc123');

final baseInstant = DateTime.utc(2026, 4, 20, 9, 14, 22);

AnnotationSession newSession({
  Anchor? initial,
  InkTool tool = InkTool.pen,
  DateTime? at,
  int undoDepth = 50,
  FakeIdGenerator? gen,
  FakeClock? clock,
  Set<PointerKind>? allowedPointerKinds,
}) {
  return AnnotationSession(
    initialAnchor: initial ?? markdownAnchor,
    tool: tool,
    clock: clock ?? FakeClock(at ?? baseInstant),
    idGenerator: gen ?? FakeIdGenerator(),
    undoDepth: undoDepth,
    allowedPointerKinds:
        allowedPointerKinds ?? const {PointerKind.stylus},
  );
}

PointerSample stylusSample(
  double x,
  double y, {
  double pressure = 0.5,
  DateTime? at,
}) {
  return PointerSample(
    x: x,
    y: y,
    pressure: pressure,
    kind: PointerKind.stylus,
    timestamp: at ?? baseInstant,
  );
}

PointerSample kindSample(PointerKind k) => PointerSample(
      x: 0,
      y: 0,
      pressure: 0.5,
      kind: k,
      timestamp: baseInstant,
    );
