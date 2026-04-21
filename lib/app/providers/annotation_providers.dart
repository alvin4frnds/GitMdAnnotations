import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job_ref.dart';
import '../../domain/entities/pointer_sample.dart';
import '../../domain/ports/clock_port.dart';
import '../../domain/ports/id_generator_port.dart';
import '../controllers/annotation_controller.dart';

/// Binds the [Clock] port at composition root. Tests override with
/// [FakeClock]; `bootstrap.dart` wires the real `SystemClock` in both real
/// and mockup modes.
final clockProvider = Provider<Clock>((ref) {
  throw UnimplementedError(
    'clockProvider must be overridden at composition root',
  );
});

/// Binds the [IdGenerator] port at composition root. Tests override with
/// [FakeIdGenerator]; `bootstrap.dart` wires the real `SystemIdGenerator`.
final idGeneratorProvider = Provider<IdGenerator>((ref) {
  throw UnimplementedError(
    'idGeneratorProvider must be overridden at composition root',
  );
});

/// Pointer kinds the annotation canvas accepts. Default `{stylus}` — palm
/// rejection per PRD §5.4 FR-1.16/FR-1.17. The composition root widens
/// the set to include mouse + touch when
/// `--dart-define=ALLOW_MOUSE_ANNOTATION=true`, which is how the Android
/// emulator / desktop dev loop exercises the canvas without a real pen.
/// Widget tests override this provider directly to drive mouse gestures.
final allowedPointerKindsProvider = Provider<Set<PointerKind>>(
  (ref) => const {PointerKind.stylus},
);

/// Per-job annotation state. Keyed on [JobRef] via `family` so each job
/// owns its own in-memory `AnnotationSession`.
///
/// Previously `autoDispose` per IMPLEMENTATION.md §2.2 ("annotation
/// sessions don't leak across jobs"), but that dropped the stroke set
/// when the user popped AnnotationCanvas, which meant the Review panel
/// saw an empty `groups` list even though the user had just drawn on
/// the canvas. Kept alive for the session so Submit Review / the
/// review-panel left-pane summary reflect the real annotations;
/// per-job scoping still comes from `family` + the `JobRef` key. The
/// `_session` is re-seeded with the saved groups when the notifier is
/// first attached, so repeated attach/detach cycles are coherent.
final annotationControllerProvider =
    NotifierProvider.family<AnnotationController, AnnotationState, JobRef>(
  AnnotationController.new,
);
