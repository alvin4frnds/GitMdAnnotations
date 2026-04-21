import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/canvas_size.dart';
import '../../domain/entities/changelog_entry.dart';
import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/source_kind.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/entities/stroke_group.dart';
import '../../domain/ports/file_system_port.dart';
import '../../domain/ports/git_port.dart';
import '../../domain/services/changelog_writer.dart';
import '../../domain/services/commit_planner.dart';
import '../../domain/services/open_question_extractor.dart';
import '../../domain/services/planned_write.dart';
import '../../domain/services/review_serializer.dart';
import '../../domain/services/svg_serializer.dart';
import '../providers/annotation_providers.dart';
import '../providers/review_providers.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';

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

/// Per-job review controller: owns typed Q&A + notes, auto-saves drafts,
/// and composes the review-submit / approve commits via the domain
/// services.
///
/// Scoped `autoDispose.family<JobRef>` so the in-memory state dies with
/// the route (consistent with `AnnotationController`). On dispose the
/// periodic auto-save timer is cancelled so Riverpod won't warn about a
/// leaked Timer.
class ReviewController
    extends AutoDisposeFamilyAsyncNotifier<ReviewState, JobRef> {
  static const Duration _autoSaveTick = Duration(seconds: 3);

  Timer? _timer;
  bool _dirty = false;
  ReviewState? _cached;

  @override
  Future<ReviewState> build(JobRef arg) async {
    final draft = await _loadDraft(arg);
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

  /// Composes and commits the typed review per PRD §5.6 FR-1.25/1.26.
  ///
  /// Happy path: SvgSerializer → PngFlattener → ReviewSerializer →
  /// ChangelogWriter → CommitPlanner → GitPort.commit. On typed
  /// invariant failure from `CommitPlanner` (or any other exception at
  /// the boundary) the submission state flips to
  /// [ReviewSubmissionFailure] with the raw error preserved for the UI
  /// layer to route through `ErrorPresenter`.
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
      final clock = ref.read(clockProvider);
      final fs = ref.read(fileSystemProvider);
      final git = ref.read(gitPortProvider);
      final pngFlattener = ref.read(pngFlattenerProvider);

      // Review body.
      final reviewMd = ReviewSerializer(clock: clock).buildReviewMd(
        job: arg,
        source: source,
        questions: questions,
        answers: state.answers,
        freeFormNotes: state.freeFormNotes,
        strokeGroups: strokeGroups,
      );

      // Annotation pair (markdown path only in Phase 1; PDF review lands
      // in a future milestone — see TabletApp-PRD §5.5).
      MarkdownAnnotations? markdownAnnotations;
      if (source.sourceKind == SourceKind.markdown) {
        final svg = const SvgSerializer().serialize(
          strokeGroups,
          SvgSource(sourceFile: source.path, sourceSha: source.sha),
        );
        final png = await pngFlattener.flatten(
          groups: strokeGroups,
          canvas: CanvasSize(width: 1024, height: 1024),
        );
        markdownAnnotations = MarkdownAnnotations(svg: svg, png: png);
      }

      // Spec/sidecar changelog bump.
      final existingChangelog = await _readExisting(
        fs,
        source.sourceKind == SourceKind.pdf
            ? _jobFile(arg, 'CHANGELOG.md')
            : source.path,
      );
      final updatedChangelog = const ChangelogWriter().append(
        existingChangelog.isEmpty && source.sourceKind == SourceKind.markdown
            ? source.contents
            : existingChangelog,
        ChangelogEntry(
          timestamp: clock.now(),
          author: 'tablet',
          description: 'Submitted review of ${_basename(source.path)}.',
        ),
      );

      final plan = const CommitPlanner().planReview(
        job: arg,
        source: source,
        reviewMd: reviewMd,
        markdownAnnotations: markdownAnnotations,
        pdfAnnotations: null,
        updatedSpecOrSidecar: updatedChangelog,
        strokeGroups: strokeGroups,
      );

      final commit = await git.commit(
        files: plan.writes.map(_toFileWrite).toList(),
        message: plan.message,
        id: identity,
        branch: 'claude-jobs',
      );

      await _deleteDraft(arg);
      _emit(_current().copyWith(
        submission: ReviewSubmissionSuccess(commit),
      ));
    } catch (e) {
      _emit(_current().copyWith(submission: ReviewSubmissionFailure(e)));
    }
  }

  /// Composes and commits the Approve commit per PRD §5.6 FR-1.27/1.28.
  /// Writes an empty `05-approved` marker + appends a changelog entry;
  /// no new annotations, no PNG flatten.
  Future<void> approve({
    required SpecFile source,
    required GitIdentity identity,
  }) async {
    _emit(_current().copyWith(
      submission: const ReviewSubmissionInProgress(),
    ));
    try {
      final clock = ref.read(clockProvider);
      final fs = ref.read(fileSystemProvider);
      final git = ref.read(gitPortProvider);

      final existingChangelog = await _readExisting(
        fs,
        source.sourceKind == SourceKind.pdf
            ? _jobFile(arg, 'CHANGELOG.md')
            : source.path,
      );
      final updatedChangelog = const ChangelogWriter().append(
        existingChangelog.isEmpty && source.sourceKind == SourceKind.markdown
            ? source.contents
            : existingChangelog,
        ChangelogEntry(
          timestamp: clock.now(),
          author: 'tablet',
          description: 'Approved ${_basename(source.path)} for implementation.',
        ),
      );

      final plan = const CommitPlanner().planApprove(
        job: arg,
        source: source,
        updatedSpecOrSidecar: updatedChangelog,
      );
      final commit = await git.commit(
        files: plan.writes.map(_toFileWrite).toList(),
        message: plan.message,
        id: identity,
        branch: 'claude-jobs',
      );
      await _deleteDraft(arg);
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
      await _saveDraft(job, _current());
      final now = ref.read(clockProvider).now();
      _emit(_current().copyWith(lastAutoSaveAt: now));
    } catch (_) {
      // Swallow — a failed auto-save must not take the whole review
      // surface down. The next mutation re-sets [_dirty] and retries.
      _dirty = true;
    }
  }

  Future<void> _saveDraft(JobRef job, ReviewState s) async {
    final fs = ref.read(fileSystemProvider);
    final path = await _draftPath(fs, job);
    final payload = jsonEncode({
      'answers': s.answers,
      'freeFormNotes': s.freeFormNotes,
    });
    await fs.writeString(path, payload);
  }

  Future<_DraftPayload?> _loadDraft(JobRef job) async {
    try {
      final fs = ref.read(fileSystemProvider);
      final path = await _draftPath(fs, job);
      final raw = await fs.readString(path);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final answers = decoded['answers'];
      final notes = decoded['freeFormNotes'];
      return _DraftPayload(
        answers: answers is Map
            ? answers.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const <String, String>{},
        freeFormNotes: notes is String ? notes : '',
      );
    } on FsNotFound {
      return null;
    } catch (_) {
      // Corrupt draft — treat as absent. The periodic auto-save will
      // overwrite on the next mutation.
      return null;
    }
  }

  Future<void> _deleteDraft(JobRef job) async {
    final fs = ref.read(fileSystemProvider);
    final path = await _draftPath(fs, job);
    await fs.remove(path);
  }

  Future<String> _draftPath(FileSystemPort fs, JobRef job) async {
    return fs.appDocsPath('drafts/${job.jobId}/03-review.md.draft');
  }

  Future<String> _readExisting(FileSystemPort fs, String path) async {
    try {
      return await fs.readString(path);
    } on FsNotFound {
      return '';
    }
  }

  String _jobFile(JobRef job, String name) =>
      'jobs/pending/${job.jobId}/$name';

  String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  FileWrite _toFileWrite(PlannedWrite p) => switch (p) {
        PlannedTextWrite(:final path, :final contents) =>
          FileWrite(path: path, contents: contents),
        PlannedBinaryWrite(:final path, :final bytes) =>
          FileWrite(path: path, contents: '', bytes: Uint8List.fromList(bytes)),
      };
}

class _DraftPayload {
  const _DraftPayload({required this.answers, required this.freeFormNotes});
  final Map<String, String> answers;
  final String freeFormNotes;
}
