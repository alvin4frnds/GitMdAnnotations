import '../entities/changelog_entry.dart';

/// Appends a [ChangelogEntry] to the `## Changelog` section of a markdown
/// file (or a sidecar `CHANGELOG.md` for PDFs). Pure domain — zero Flutter /
/// `dart:io`. Output uses LF line endings only.
///
/// Canonical line shape per IMPLEMENTATION.md §3.3 and PRD §8.3:
/// `- YYYY-MM-DD HH:mm <author>: <description>`.
class ChangelogWriter {
  const ChangelogWriter();

  /// Returns a new string: [existing] with [entry] appended to its
  /// `## Changelog` section. If the section is missing, it is created at the
  /// end of the file, preceded by a single blank line for separation.
  ///
  /// CRLF input is normalized to LF in the returned value (a single code path
  /// is simpler than branching on line-ending style).
  ///
  /// Idempotency: if the formatted line is byte-equal to any line already
  /// present in [existing], the original [existing] is returned unchanged
  /// (pre-normalization). Callers who want a canonicalized file should
  /// re-read it after commit; this method does not rewrite byte-identical
  /// inputs.
  String append(String existing, ChangelogEntry entry) {
    final line = formatLine(entry);
    final normalized = existing.replaceAll('\r\n', '\n');
    if (_containsLine(normalized, line)) {
      return existing;
    }
    if (normalized.isEmpty) {
      return '## Changelog\n\n$line\n';
    }
    final headerIdx = _findChangelogHeader(normalized);
    if (headerIdx < 0) {
      final withTrailing =
          normalized.endsWith('\n') ? normalized : '$normalized\n';
      return '$withTrailing\n## Changelog\n\n$line\n';
    }
    return _insertIntoSection(normalized, headerIdx, line);
  }

  /// Format a single entry as its canonical bullet line. Exposed so callers
  /// (e.g. `ReviewSerializer`) can assemble entries inline.
  ///
  /// Throws [ArgumentError] if [ChangelogEntry.author] or
  /// [ChangelogEntry.description] is empty.
  String formatLine(ChangelogEntry entry) {
    if (entry.author.isEmpty) {
      throw ArgumentError.value(
        entry.author,
        'entry.author',
        'must not be empty',
      );
    }
    if (entry.description.isEmpty) {
      throw ArgumentError.value(
        entry.description,
        'entry.description',
        'must not be empty',
      );
    }
    final t = entry.timestamp;
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '- $y-$mo-$d $h:$mi ${entry.author}: ${entry.description}';
  }

  bool _containsLine(String text, String line) {
    for (final l in text.split('\n')) {
      if (l == line) return true;
    }
    return false;
  }

  int _findChangelogHeader(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] == '## Changelog') return i;
    }
    return -1;
  }

  String _insertIntoSection(String text, int headerIdx, String line) {
    final lines = text.split('\n');
    var endIdx = lines.length;
    for (var i = headerIdx + 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) {
        endIdx = i;
        break;
      }
    }
    var insertAt = endIdx;
    while (insertAt > headerIdx + 1 && lines[insertAt - 1].isEmpty) {
      insertAt--;
    }
    lines.insert(insertAt, line);
    final out = lines.join('\n');
    return out.endsWith('\n') ? out : '$out\n';
  }
}
