import '../../domain/entities/commit.dart';

/// Sealed progress state for a review submission (typed Submit/Approve).
///
/// UI widgets `switch` exhaustively on concrete subtypes to drive buttons
/// between enabled / pending / success / failure. Terminal states are
/// [ReviewSubmissionSuccess] and [ReviewSubmissionFailure]; a fresh
/// `submit` call always transitions through
/// [ReviewSubmissionInProgress] first.
sealed class ReviewSubmission {
  const ReviewSubmission();
}

class ReviewSubmissionIdle extends ReviewSubmission {
  const ReviewSubmissionIdle();
}

class ReviewSubmissionInProgress extends ReviewSubmission {
  const ReviewSubmissionInProgress();
}

class ReviewSubmissionSuccess extends ReviewSubmission {
  const ReviewSubmissionSuccess(this.commit);
  final Commit commit;
}

class ReviewSubmissionFailure extends ReviewSubmission {
  const ReviewSubmissionFailure(this.error);
  final Object error;
}

/// UI-facing state for the typed review panel. Fields mirror the FR-1.22–
/// FR-1.28 surface: per-question answers, free-form notes, last-saved
/// timestamp for the "auto-saved Ns ago" caption, and the submission
/// lifecycle.
class ReviewState {
  const ReviewState({
    required this.answers,
    required this.freeFormNotes,
    required this.lastAutoSaveAt,
    required this.submission,
  });

  const ReviewState.initial()
      : answers = const <String, String>{},
        freeFormNotes = '',
        lastAutoSaveAt = null,
        submission = const ReviewSubmissionIdle();

  final Map<String, String> answers;
  final String freeFormNotes;
  final DateTime? lastAutoSaveAt;
  final ReviewSubmission submission;

  ReviewState copyWith({
    Map<String, String>? answers,
    String? freeFormNotes,
    DateTime? lastAutoSaveAt,
    ReviewSubmission? submission,
  }) =>
      ReviewState(
        answers: answers ?? this.answers,
        freeFormNotes: freeFormNotes ?? this.freeFormNotes,
        // `lastAutoSaveAt` may legitimately remain null across copies; the
        // usual "?? this.lastAutoSaveAt" pattern would mask a deliberate
        // clear. Callers that need clearing can pass a sentinel via
        // [copyWithClearLastAutoSaveAt] below — unused in Phase 1.
        lastAutoSaveAt: lastAutoSaveAt ?? this.lastAutoSaveAt,
        submission: submission ?? this.submission,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReviewState) return false;
    if (other.freeFormNotes != freeFormNotes) return false;
    if (other.lastAutoSaveAt != lastAutoSaveAt) return false;
    if (other.submission != submission) return false;
    if (other.answers.length != answers.length) return false;
    for (final entry in answers.entries) {
      if (other.answers[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(answers.entries.map((e) => Object.hash(e.key, e.value))),
        freeFormNotes,
        lastAutoSaveAt,
        submission,
      );

  @override
  String toString() =>
      'ReviewState(answers: ${answers.length}, notes: ${freeFormNotes.length} chars, '
      'lastAutoSaveAt: $lastAutoSaveAt, submission: $submission)';
}
