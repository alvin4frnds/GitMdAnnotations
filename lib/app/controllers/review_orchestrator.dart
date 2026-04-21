import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/services/open_question_extractor.dart';
import '../providers/annotation_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/spec_providers.dart';
import 'auth_controller.dart';

/// Sealed result of the orchestrator assembling context for the Review
/// panel's Submit / Approve flows. The UI layer switches exhaustively to
/// either present the confirmation dialog or surface an error.
///
/// No dialog presentation lives in this file — that seam is in the
/// Review panel widget so the orchestrator can be unit-tested against a
/// plain `ProviderContainer` with zero widget pumping.
sealed class ReviewOrchestratorOutcome {
  const ReviewOrchestratorOutcome();
}

class ReviewOrchestratorReady extends ReviewOrchestratorOutcome {
  const ReviewOrchestratorReady({
    required this.source,
    required this.questions,
    required this.strokeGroups,
    required this.identity,
  });
  final SpecFile source;
  final List<OpenQuestion> questions;
  final List<StrokeGroup> strokeGroups;
  final GitIdentity identity;
}

class ReviewOrchestratorSignInRequired extends ReviewOrchestratorOutcome {
  const ReviewOrchestratorSignInRequired();
}

class ReviewOrchestratorSpecUnavailable extends ReviewOrchestratorOutcome {
  const ReviewOrchestratorSpecUnavailable();
}

/// Thin helper that assembles the inputs the Submit / Approve
/// confirmation dialogs need. Split out of the Review panel widget so
/// assembly can be unit-tested directly against a `ProviderContainer`
/// without pumping any widgets.
///
/// Placement: the orchestrator is intentionally external to the modal
/// (not inside its primary-button tap) because the modal already takes
/// the fully-assembled inputs as required constructor args — calling
/// `prepare` and then launching `showDialog` is the natural separation,
/// and a sign-in-required error must be surfaced BEFORE the modal opens
/// (not after it's on screen with stale inputs).
class ReviewOrchestrator {
  const ReviewOrchestrator(this._read);

  /// Injected `Ref.read`-like function so the helper can be used from
  /// either a widget's `WidgetRef` or a test's `ProviderContainer`
  /// without caring which.
  final T Function<T>(ProviderListenable<T>) _read;

  /// Reads the current signed-in identity, the spec for [job], and the
  /// stroke groups drawn on the annotation canvas; returns one of the
  /// three sealed outcomes.
  Future<ReviewOrchestratorOutcome> prepare(JobRef job) async {
    // Use `.future` so the AsyncNotifier's `build` finishes if it hasn't
    // yet — without this, an eager tap on Submit Review during restore
    // would see an `AsyncLoading` value and always short-circuit to
    // `SignInRequired`.
    final authState = await _read(authControllerProvider.future);
    if (authState is! AuthSignedIn) {
      return const ReviewOrchestratorSignInRequired();
    }
    final source = await _read(specFileProvider(job).future);
    if (source == null) {
      return const ReviewOrchestratorSpecUnavailable();
    }
    final questions =
        const OpenQuestionExtractor().extract(source.contents);
    final strokeGroups =
        _read(annotationControllerProvider(job)).groups;
    return ReviewOrchestratorReady(
      source: source,
      questions: questions,
      strokeGroups: List.unmodifiable(strokeGroups),
      identity: authState.session.identity,
    );
  }
}
