import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/services/open_question_extractor.dart';
import '../providers/annotation_providers.dart';
import '../providers/review_providers.dart';
import '../providers/sync_providers.dart';
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

/// Factory that produces a periodic [Timer]. Pulled into a typedef so
/// tests can inject a manual driver (see
/// `reviewAutoSaveTimerFactoryProvider`) and step the tick deterministically
/// without sleeping. Production wiring (`bootstrap.dart` default) returns
/// `Timer.periodic`.
typedef PeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer) callback,
);

/// Per-job review controller: owns typed Q&A + notes, auto-saves drafts,
/// and composes the review-submit / approve commits via the domain
/// services.
///
/// Scoped `autoDispose.family<JobRef>` so the in-memory state dies with
/// the route (consistent with `AnnotationController`). On dispose the
/// periodic auto-save timer is cancelled so Riverpod won't warn about a
/// leaked Timer, and any pending dirty edits are flushed with a final
/// save so keystrokes made within the last tick window aren't lost.
///
/// The controller itself is a thin state-machine over two collaborators
/// fetched from providers:
///   * [ReviewDraftStore] — draft load / save / delete I/O.
///   * [ReviewSubmitter]  — domain-service composition for submit /
///                          approve commits.
/// Splitting these out keeps this file under the §2.6 200-line cap.
class ReviewController
    extends AutoDisposeFamilyAsyncNotifier<ReviewState, JobRef> {
  Timer? _timer;
  bool _dirty = false;
  bool _persisting = false;
  ReviewState? _cached;

  ReviewDraftStore get _draftStore => ref.read(reviewDraftStoreProvider);
  ReviewSubmitter get _submitter => ref.read(reviewSubmitterProvider);

  @override
  Future<ReviewState> build(JobRef arg) async {
    final draftStore = ref.read(reviewDraftStoreProvider);
    final draft = await draftStore.load(arg);
    final tick = ref.read(reviewAutoSaveIntervalProvider);
    final factory = ref.read(reviewAutoSaveTimerFactoryProvider);
    // Capture the draft store reference out of [ref] so the dispose
    // callback doesn't touch the (already-disposing) provider container.
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      // Pop-save: flush any edits that happened inside the last tick
      // window. Fire-and-forget — the notifier is disposing, there's no
      // state left to update. The draft store is a pure FS helper so it
      // completes safely independent of the Riverpod container lifecycle.
      if (_dirty && !_persisting) {
        _dirty = false;
        final s = _current();
        unawaited(draftStore.save(
          arg,
          answers: s.answers,
          freeFormNotes: s.freeFormNotes,
        ));
      }
      // Null [_cached] so any still-running [_maybePersist] task bails
      // before touching `state` (which throws post-dispose).
      _cached = null;
    });
    // Periodic failsafe: a dirty draft is coalesced onto disk within one
    // tick (default 5 s). In-flight writes are skipped rather than
    // queued — the next tick picks up whatever the latest state is.
    _timer = factory(tick, (_) => _maybePersist(arg));
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

  /// Mutates the answer for [questionId] and marks the draft dirty. The
  /// periodic auto-save tick (see `reviewAutoSaveIntervalProvider`) picks
  /// up the change on its next fire. Keystroke bursts therefore coalesce
  /// into at most one disk write per tick.
  void setAnswer(String questionId, String value) {
    final current = _current();
    if (current.answers[questionId] == value) return;
    final next = Map<String, String>.from(current.answers)
      ..[questionId] = value;
    _emit(current.copyWith(answers: next));
    _dirty = true;
  }

  /// Replaces the free-form notes body and marks the draft dirty. Disk
  /// persistence happens on the next auto-save tick or on controller
  /// dispose (pop-save), whichever comes first.
  void setFreeFormNotes(String value) {
    final current = _current();
    if (current.freeFormNotes == value) return;
    _emit(current.copyWith(freeFormNotes: value));
    _dirty = true;
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
      // JobList's Sync Up badge needs to re-count unpushed commits.
      ref.invalidate(pendingPushCountProvider);
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
      ref.invalidate(pendingPushCountProvider);
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

  /// Tick handler for the periodic auto-save timer. Writes the current
  /// draft only when it has changed since the last successful save, and
  /// skips outright while a previous write is still in flight — this
  /// guarantees we never stack duplicate writes against the FS port.
  Future<void> _maybePersist(JobRef job) async {
    if (!_dirty || _persisting) return;
    _persisting = true;
    _dirty = false;
    try {
      final s = _current();
      await _draftStore.save(
        job,
        answers: s.answers,
        freeFormNotes: s.freeFormNotes,
      );
      if (_cached == null) return; // disposed mid-save
      final now = ref.read(clockProvider).now();
      _emit(_current().copyWith(lastAutoSaveAt: now));
    } catch (_) {
      // Swallow — a failed auto-save must not take the whole review
      // surface down. Re-mark dirty so the next tick retries.
      _dirty = true;
    } finally {
      _persisting = false;
    }
  }
}
