import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/services/open_question_extractor.dart';
import '../providers/annotation_providers.dart';
import '../providers/review_providers.dart';
import 'review_draft_store.dart';
import 'review_state.dart';
import 'review_submitter.dart';

// Re-export the sealed submission and state types so existing callers —
// including widget code and tests — can keep importing a single symbol
// surface from `review_controller.dart`. The canonical definitions live
// in `review_state.dart`.
export 'review_state.dart'
    show
        ReviewState,
        ReviewSubmission,
        ReviewSubmissionIdle,
        ReviewSubmissionInProgress,
        ReviewSubmissionSuccess,
        ReviewSubmissionFailure;

/// Per-job review controller: owns typed Q&A + notes, auto-saves drafts,
/// and composes the review-submit / approve commits via the domain
/// services.
///
/// Scoped `autoDispose.family<JobRef>` so the in-memory state dies with
/// the route (consistent with `AnnotationController`). On dispose the
/// periodic auto-save timer is cancelled so Riverpod won't warn about a
/// leaked Timer.
///
/// The controller itself is a thin state-machine over two collaborators
/// fetched from providers:
///   * [ReviewDraftStore] — draft load / save / delete I/O.
///   * [ReviewSubmitter]  — domain-service composition for submit /
///                          approve commits.
/// Splitting these out keeps this file under the §2.6 200-line cap.
class ReviewController
    extends AutoDisposeFamilyAsyncNotifier<ReviewState, JobRef> {
  static const Duration _autoSaveTick = Duration(seconds: 3);

  Timer? _timer;
  bool _dirty = false;
  ReviewState? _cached;

  ReviewDraftStore get _draftStore => ref.read(reviewDraftStoreProvider);
  ReviewSubmitter get _submitter => ref.read(reviewSubmitterProvider);

  @override
  Future<ReviewState> build(JobRef arg) async {
    final draft = await _draftStore.load(arg);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    // Periodic failsafe: if a microtask-driven save ever misses an edit,
    // the periodic tick picks it up within 3 s. Tests never depend on
    // this — every observable save path fires via [_schedulePersist].
    _timer = Timer.periodic(_autoSaveTick, (_) => _maybePersist(arg));
    final initial = ReviewState(
      answers: draft?.answers ?? const <String, String>{},
      freeFormNotes: draft?.freeFormNotes ?? '',
      lastAutoSaveAt: null,
      submission: const ReviewSubmissionIdle(),
    );
    _cached = initial;
    return initial;
  }

  // -- Intents --------------------------------------------------------

  /// Mutates the answer for [questionId] and schedules a draft save.
  void setAnswer(String questionId, String value) {
    final current = _current();
    final next = Map<String, String>.from(current.answers)
      ..[questionId] = value;
    _emit(current.copyWith(answers: next));
    _dirty = true;
    _schedulePersist(arg);
  }

  /// Replaces the free-form notes body and schedules a draft save.
  void setFreeFormNotes(String value) {
    final current = _current();
    _emit(current.copyWith(freeFormNotes: value));
    _dirty = true;
    _schedulePersist(arg);
  }

  // -- Submit / Approve ----------------------------------------------

  /// Delegates the Submit Review composition to [ReviewSubmitter] and
  /// maps its return / throw into the sealed [ReviewSubmission] state.
  Future<void> submit({
    required SpecFile source,
    required List<OpenQuestion> questions,
    required List<StrokeGroup> strokeGroups,
    required GitIdentity identity,
  }) async {
    _emit(_current().copyWith(
      submission: const ReviewSubmissionInProgress(),
    ));
    try {
      final state = _current();
      final commit = await _submitter.submit(
        job: arg,
        source: source,
        questions: questions,
        answers: state.answers,
        freeFormNotes: state.freeFormNotes,
        strokeGroups: strokeGroups,
        identity: identity,
      );
      await _draftStore.delete(arg);
      _emit(_current().copyWith(
        submission: ReviewSubmissionSuccess(commit),
      ));
    } catch (e) {
      _emit(_current().copyWith(submission: ReviewSubmissionFailure(e)));
    }
  }

  /// Delegates the Approve composition to [ReviewSubmitter]; same
  /// failure-mapping contract as [submit].
  Future<void> approve({
    required SpecFile source,
    required GitIdentity identity,
  }) async {
    _emit(_current().copyWith(
      submission: const ReviewSubmissionInProgress(),
    ));
    try {
      final commit = await _submitter.approve(
        job: arg,
        source: source,
        identity: identity,
      );
      await _draftStore.delete(arg);
      _emit(_current().copyWith(
        submission: ReviewSubmissionSuccess(commit),
      ));
    } catch (e) {
      _emit(_current().copyWith(submission: ReviewSubmissionFailure(e)));
    }
  }

  // -- Internals -----------------------------------------------------

  /// Current state — preferring the locally cached value set by [_emit]
  /// so intent handlers don't race with the AsyncValue wrapping.
  ReviewState _current() => _cached ?? const ReviewState.initial();

  void _emit(ReviewState next) {
    _cached = next;
    state = AsyncValue.data(next);
  }

  /// Schedule a draft save on the next microtask. Coalesces bursts of
  /// keystrokes — multiple `setAnswer` calls in one frame only yield one
  /// disk write.
  void _schedulePersist(JobRef job) {
    // A single microtask is enough: if the notifier disposes before it
    // runs, the scheduled call sees [_dirty] flipped false via the
    // post-build guard inside [_maybePersist].
    scheduleMicrotask(() => _maybePersist(job));
  }

  Future<void> _maybePersist(JobRef job) async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final s = _current();
      await _draftStore.save(
        job,
        answers: s.answers,
        freeFormNotes: s.freeFormNotes,
      );
      final now = ref.read(clockProvider).now();
      _emit(_current().copyWith(lastAutoSaveAt: now));
    } catch (_) {
      // Swallow — a failed auto-save must not take the whole review
      // surface down. The next mutation re-sets [_dirty] and retries.
      _dirty = true;
    }
  }
}
