import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job_ref.dart';
import '../../domain/ports/png_flattener_port.dart';
import '../controllers/review_controller.dart';
import '../controllers/review_draft_store.dart';
import '../controllers/review_submitter.dart';
import 'annotation_providers.dart';
import 'spec_providers.dart';
import 'sync_providers.dart';

/// Binds the [PngFlattener] port at composition root. Tests override
/// with [FakePngFlattener]; `bootstrap.dart` wires the real
/// `PngFlattenerAdapter`. Added in T7 — the review-submit pipeline is
/// the first production consumer of the port that needs a provider
/// binding (the T4 domain tests composed the port manually).
final pngFlattenerProvider = Provider<PngFlattener>((ref) {
  throw UnimplementedError(
    'pngFlattenerProvider must be overridden at composition root',
  );
});

/// Pure persistence helper for the per-job review draft. Recomputed when
/// [fileSystemProvider] is replaced so test fakes propagate automatically.
final reviewDraftStoreProvider = Provider<ReviewDraftStore>(
  (ref) => ReviewDraftStore(ref.watch(fileSystemProvider)),
);

/// Stateless composition of the domain-service stack for Submit Review
/// and Approve commits. Recomputed when any bound port is replaced.
final reviewSubmitterProvider = Provider<ReviewSubmitter>(
  (ref) => ReviewSubmitter(
    clock: ref.watch(clockProvider),
    fs: ref.watch(fileSystemProvider),
    git: ref.watch(gitPortProvider),
    pngFlattener: ref.watch(pngFlattenerProvider),
    markdownRasterizer: ref.watch(markdownRasterizerProvider),
  ),
);

/// Per-job typed review state, scoped to the route via `autoDispose` and
/// keyed on [JobRef] via `family`. Draft resume, auto-save, and the
/// Submit/Approve composition all live in [ReviewController].
///
/// Follows the T5 `annotationControllerProvider` pattern with one
/// difference: because [ReviewController] does asynchronous work
/// (draft load in `build`), it's an `AsyncNotifierProvider` flavor.
final reviewControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewController, ReviewState, JobRef>(
  ReviewController.new,
);

/// Tick interval for the [ReviewController] auto-save timer. Defaults to
/// 5 seconds per the Phase 1 plan (docs/implementation-plan2.md W4.3).
/// Tests override this provider with a tiny [Duration] so `Timer.periodic`
/// doesn't sleep the suite for 5 real seconds — combined with
/// `reviewAutoSaveTimerFactoryProvider` below, auto-save behavior is
/// deterministic in unit tests.
final reviewAutoSaveIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Factory for the periodic [Timer] that drives [ReviewController]
/// auto-save. Production default is `Timer.periodic`; tests inject a
/// manual driver that records the registered callback and exposes a
/// `fire()` hook so ticks are observable without real time passing.
final reviewAutoSaveTimerFactoryProvider = Provider<PeriodicTimerFactory>(
  (ref) => Timer.periodic,
);
