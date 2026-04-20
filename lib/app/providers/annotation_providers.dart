import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job_ref.dart';
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

/// Per-job annotation state, scoped to the route via `autoDispose`. When no
/// widget is listening (the SpecReader screen pops), Riverpod drops the
/// notifier and its [AnnotationSession] — cold state on next navigation
/// matches the PRD requirement that "annotation sessions don't leak across
/// jobs" (IMPLEMENTATION.md §2.2).
final annotationControllerProvider = NotifierProvider.autoDispose
    .family<AnnotationController, AnnotationState, JobRef>(
  AnnotationController.new,
);
