/// A single entry under the `## Open questions` section of a spec.
/// [id] is like `Q1` / `Q2a`; [body] is the question text with any
/// continuation lines joined by single spaces.
class OpenQuestion {
  const OpenQuestion({required this.id, required this.body});

  final String id;
  final String body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenQuestion && other.id == id && other.body == body;

  @override
  int get hashCode => Object.hash(id, body);

  @override
  String toString() => 'OpenQuestion(id: $id, body: $body)';
}

/// Parses the `## Open questions` section of a spec markdown file into
/// a flat list of [OpenQuestion]s. See IMPLEMENTATION.md §3.5 / §4.3.
///
/// Recognised entry forms inside the section:
///   * `### Q<digits>[a-z]*: <body>`   (any level-3+ heading)
///   * `<N>. Q<digits>[a-z]*: <body>`  (numbered list)
///   * `- Q<digits>[a-z]*: <body>`     (bullet list)
///
/// Section header matching is case-insensitive with trim. The section
/// ends at the next `## ` heading or EOF. Continuation lines before a
/// blank line are concatenated into the body with single spaces.
class OpenQuestionExtractor {
  const OpenQuestionExtractor();

  static final RegExp _sectionHeader =
      RegExp(r'^\s*##\s+open\s+questions\s*$');
  static final RegExp _heading =
      RegExp(r'^\s*#{2,6}\s+(Q\d+[a-z]*)\s*:\s*(.*)$');
  static final RegExp _numbered =
      RegExp(r'^\s*\d+\.\s+(Q\d+[a-z]*)\s*:\s*(.*)$');
  static final RegExp _bullet =
      RegExp(r'^\s*-\s+(Q\d+[a-z]*)\s*:\s*(.*)$');
  static final RegExp _anyLevel2 = RegExp(r'^\s*##\s+');

  List<OpenQuestion> extract(String markdown) {
    final lines = markdown.split('\n');
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_sectionHeader.hasMatch(lines[i].toLowerCase())) {
        start = i + 1;
        break;
      }
    }
    if (start < 0) return const [];

    final out = <OpenQuestion>[];
    String? currentId;
    final body = StringBuffer();
    void flush() {
      if (currentId != null) {
        out.add(OpenQuestion(id: currentId!, body: body.toString().trim()));
      }
      currentId = null;
      body.clear();
    }

    for (var i = start; i < lines.length; i++) {
      final line = lines[i].replaceFirst(RegExp(r'\s+$'), '');
      if (_anyLevel2.hasMatch(line)) {
        flush();
        break;
      }
      final match = _matchEntry(line);
      if (match != null) {
        flush();
        currentId = match.$1;
        if (match.$2.isNotEmpty) body.write(match.$2);
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      if (currentId != null) {
        if (body.isNotEmpty) body.write(' ');
        body.write(line.trimLeft());
      }
    }
    flush();
    return List.unmodifiable(out);
  }

  (String, String)? _matchEntry(String line) {
    final h = _heading.firstMatch(line);
    if (h != null) return (h.group(1)!, h.group(2)!.trim());
    final n = _numbered.firstMatch(line);
    if (n != null) return (n.group(1)!, n.group(2)!.trim());
    final b = _bullet.firstMatch(line);
    if (b != null) return (b.group(1)!, b.group(2)!.trim());
    return null;
  }
}
