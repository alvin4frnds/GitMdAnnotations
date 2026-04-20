/// One line of the `## Changelog` section (IMPLEMENTATION.md §3.3).
///
/// Per decision D-14 the [timestamp] is local time — the writing device's
/// clock — with no timezone suffix. [author] is a free-form string
/// (`tablet`, `desktop`, future agent names).
class ChangelogEntry {
  const ChangelogEntry({
    required this.timestamp,
    required this.author,
    required this.description,
  });

  final DateTime timestamp;
  final String author;
  final String description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangelogEntry &&
          other.timestamp == timestamp &&
          other.author == author &&
          other.description == description;

  @override
  int get hashCode => Object.hash(timestamp, author, description);

  @override
  String toString() =>
      'ChangelogEntry(timestamp: $timestamp, author: $author, description: $description)';
}
