import '../entities/changelog_entry.dart';

/// Strict parser for the `## Changelog` section at the bottom of a spec /
/// review markdown file (or sidecar `CHANGELOG.md` for PDFs).
///
/// Originally colocated with [FakeGitPort]; promoted to `services/` in T9 so
/// that [SpecRepository] can share the single parser implementation. The
/// shipping git adapter (T10) will call straight into this function — no
/// forked copy.
///
/// Contract: missing section -> empty list; malformed entries ->
/// [FormatException]. Timestamps are local time per PRD §8.3 / D-14
/// (no timezone suffix).
List<ChangelogEntry> parseChangelog(String markdown) {
  final lines = markdown.split('\n');
  final headerIdx = lines.indexWhere((l) => l.trim() == '## Changelog');
  if (headerIdx < 0) return const [];
  final entries = <ChangelogEntry>[];
  for (var i = headerIdx + 1; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('## ')) break;
    if (!line.startsWith('- ')) continue;
    entries.add(_parseEntry(line));
  }
  return entries;
}

final RegExp _entryLine =
    RegExp(r'^- (\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}) ([^:]+): (.+)$');

ChangelogEntry _parseEntry(String line) {
  final m = _entryLine.firstMatch(line);
  if (m == null) {
    throw FormatException('Malformed changelog entry: "$line"');
  }
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  _validateDate(year, month, day, hour, minute, line);
  return ChangelogEntry(
    timestamp: DateTime(year, month, day, hour, minute),
    author: m.group(6)!.trim(),
    description: m.group(7)!.trim(),
  );
}

void _validateDate(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  String line,
) {
  if (month < 1 || month > 12) _bail(line);
  if (day < 1 || day > 31) _bail(line);
  if (hour > 23 || minute > 59) _bail(line);
  final rebuilt = DateTime(year, month, day, hour, minute);
  if (rebuilt.year != year ||
      rebuilt.month != month ||
      rebuilt.day != day ||
      rebuilt.hour != hour ||
      rebuilt.minute != minute) {
    _bail(line);
  }
}

Never _bail(String line) =>
    throw FormatException('Malformed changelog entry: "$line"');
