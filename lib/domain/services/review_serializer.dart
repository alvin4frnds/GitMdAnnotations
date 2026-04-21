import '../entities/anchor.dart';
import '../entities/job_ref.dart';
import '../entities/source_kind.dart';
import '../entities/spec_file.dart';
import '../entities/stroke_group.dart';
import '../ports/clock_port.dart';
import 'open_question_extractor.dart';

/// Serializes a job review into the canonical `03-review.md` form defined in
/// IMPLEMENTATION.md §3.5 / PRD §8.5. Pure domain — no Flutter, no `dart:io`.
///
/// The wall-clock used for the `Reviewed at:` line is obtained via the
/// injected [Clock] (never `DateTime.now()`), so tests can drive deterministic
/// output with `FakeClock`.
class ReviewSerializer {
  const ReviewSerializer({required Clock clock}) : _clock = clock;

  final Clock _clock;

  /// Single capital-letter alphabet used to label stroke groups in the
  /// `## Spatial references` section: index 0 → A, 25 → Z. A 27th group
  /// throws [StateError]; multi-letter overflow (AA, AB, …) is a deferred
  /// future extension to keep the MVP surface tight.
  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Renders a review markdown document. Output uses LF newlines and always
  /// ends in exactly one trailing newline.
  ///
  /// Content contract (per IMPLEMENTATION.md §3.5):
  ///   * `answers` missing a key for a question → an empty quote line `> `
  ///     is emitted so the section structure stays visible.
  ///   * Empty `freeFormNotes` → the `## Free-form notes` section is omitted
  ///     entirely (no header, no trailing blank).
  ///   * Empty `strokeGroups` → the `## Spatial references` section is
  ///     omitted entirely.
  ///   * Answers and notes are emitted verbatim; callers own any escaping.
  String buildReviewMd({
    required JobRef job,
    required SpecFile source,
    required List<OpenQuestion> questions,
    required Map<String, String> answers,
    required String freeFormNotes,
    required List<StrokeGroup> strokeGroups,
  }) {
    _assertStrokeGroupCapacity(strokeGroups.length);

    // Call the clock exactly once — the whole document shares the same
    // review timestamp.
    final reviewedAt = _formatLocalStamp(_clock.now());

    final buf = StringBuffer()
      ..writeln('# Review \u2014 ${job.jobId}')
      ..writeln('**Source:** ${_sourceLine(source)}')
      ..writeln('**Reviewed at:** $reviewedAt local time')
      ..writeln();

    _writeAnswers(buf, questions, answers);

    if (freeFormNotes.isNotEmpty) {
      _writeFreeFormNotes(buf, freeFormNotes);
    }
    if (strokeGroups.isNotEmpty) {
      _writeSpatialReferences(buf, strokeGroups);
    }

    return _trimTrailingBlankLines(buf.toString());
  }

  /// §3.5 reading: markdown source → `02-spec.md @ <sha>`; PDF source →
  /// `spec.pdf` with no `@ <sha>` segment. Filename is the basename of
  /// [source.path] so the canonical `jobs/pending/...` prefix is stripped.
  String _sourceLine(SpecFile source) {
    final name = _basename(source.path);
    if (source.sourceKind == SourceKind.pdf) {
      return name;
    }
    return '$name @ ${source.sha}';
  }

  String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  void _writeAnswers(
    StringBuffer buf,
    List<OpenQuestion> questions,
    Map<String, String> answers,
  ) {
    buf.writeln('## Answers to open questions');
    buf.writeln();
    for (final q in questions) {
      buf.writeln('### ${q.id}: ${q.body}');
      // Missing answer → empty quote line so the section stays visible.
      final answer = answers[q.id] ?? '';
      buf.writeln(answer.isEmpty ? '> ' : '> $answer');
      buf.writeln();
    }
  }

  void _writeFreeFormNotes(StringBuffer buf, String notes) {
    buf.writeln('## Free-form notes');
    buf.writeln();
    buf.writeln(notes);
    buf.writeln();
  }

  void _writeSpatialReferences(StringBuffer buf, List<StrokeGroup> groups) {
    buf.writeln('## Spatial references');
    buf.writeln();
    for (var i = 0; i < groups.length; i++) {
      buf.writeln('- Stroke group ${_letters[i]} \u2192 ${_anchorRef(groups[i].anchor)}');
    }
    buf.writeln();
  }

  /// §3.5 shows `(description)` parentheticals (e.g. "line 47 (session
  /// store)"). Callers in Phase 1 don't supply per-group descriptions yet;
  /// emitting bare `line N` / `page N` is the minimal viable shape. Adding
  /// an optional `description` on `StrokeGroup` is a future extension.
  String _anchorRef(Anchor anchor) {
    switch (anchor) {
      case MarkdownAnchor(:final lineNumber):
        return 'line $lineNumber';
      case PdfAnchor(:final page):
        return 'page $page';
    }
  }

  void _assertStrokeGroupCapacity(int count) {
    if (count > _letters.length) {
      throw StateError(
        'ReviewSerializer supports at most ${_letters.length} stroke groups '
        '(A..Z); received $count. Multi-letter labels (AA, AB, ...) are a '
        'deferred future extension.',
      );
    }
  }

  /// `writeln` appends a trailing `\n` after each block, which leaves a
  /// dangling blank line at the end of the document. Collapse any trailing
  /// blank lines down to exactly one LF to meet the single-trailing-newline
  /// contract.
  String _trimTrailingBlankLines(String s) {
    var end = s.length;
    while (end > 1 && s[end - 1] == '\n' && s[end - 2] == '\n') {
      end--;
    }
    return s.substring(0, end);
  }
}

/// Formats a local wall-clock [DateTime] as `YYYY-MM-DD HH:mm`. The clock is
/// assumed to already be expressed in local time — the serializer never
/// converts timezones (IMPLEMENTATION.md §3.3, §3.5, D-14).
String _formatLocalStamp(DateTime t) {
  final y = t.year.toString().padLeft(4, '0');
  final mo = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  final h = t.hour.toString().padLeft(2, '0');
  final mi = t.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}
