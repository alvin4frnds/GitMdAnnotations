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
    if (normalized.isEmpty) {
      return '## Changelog\n\n$line\n';
    }
    final headerIdx = _findChangelogHeader(normalized);
    if (headerIdx < 0) {
      final withTrailing =
          normalized.endsWith('\n') ? normalized : '$normalized\n';
      return '$withTrailing\n## Changelog\n\n$line\n';
    }
    // Scope duplicate detection to the Changelog section only: a byte-equal
    // occurrence anywhere else (e.g. a quoted bullet in an Answers block,
    // a code fence) must NOT silently drop the new entry.
    if (_containsLineInSection(normalized, headerIdx, line)) {
      return existing;
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

  /// Scan only the Changelog section for a byte-equal [line]. Section
  /// boundary matches [_insertIntoSection]: from the line AFTER the
  /// `## Changelog` header up to (but not including) the next line starting
  /// with `## `, else EOF.
  bool _containsLineInSection(String text, int headerIdx, String line) {
    final lines = text.split('\n');
    var endIdx = lines.length;
    for (var i = headerIdx + 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) {
        endIdx = i;
        break;
      }
    }
    for (var i = headerIdx + 1; i < endIdx; i++) {
      if (lines[i] == line) return true;
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
    // Detect whether the section currently has any non-empty content
    // (bullet or otherwise) between the header and the section boundary.
    var hasContent = false;
    for (var i = headerIdx + 1; i < endIdx; i++) {
      if (lines[i].isNotEmpty) {
        hasContent = true;
        break;
      }
    }
    var insertAt = endIdx;
    while (insertAt > headerIdx + 1 && lines[insertAt - 1].isEmpty) {
      insertAt--;
    }
    // Canonical shape per IMPLEMENTATION.md §3.3: blank line after header
    // before first bullet. When this new bullet becomes the FIRST bullet in
    // an existing section, ensure a blank separator line exists between
    // `## Changelog` and the bullet.
    if (!hasContent && insertAt == headerIdx + 1) {
      lines.insert(insertAt, '');
      insertAt++;
    }
    lines.insert(insertAt, line);
    final out = lines.join('\n');
    return out.endsWith('\n') ? out : '$out\n';
  }
}
