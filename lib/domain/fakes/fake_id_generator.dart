import '../ports/id_generator_port.dart';

/// Deterministic [IdGenerator] for domain tests. Emits
/// `<prefix>A`, `<prefix>B`, … `<prefix>Z`, `<prefix>AA`, `<prefix>AB`, …
/// forever. Default prefix `stroke-group-` matches the SVG
/// `id="stroke-group-A"` convention from IMPLEMENTATION.md §3.4.
class FakeIdGenerator implements IdGenerator {
  FakeIdGenerator({this.prefix = 'stroke-group-'});

  final String prefix;

  /// Zero-based index of the next id to issue.
  int _i = 0;

  @override
  String next() {
    final suffix = _encode(_i);
    _i++;
    return '$prefix$suffix';
  }

  /// Base-26 A..Z suffix. 0 -> A, 25 -> Z, 26 -> AA, 27 -> AB, ...
  /// Mirrors spreadsheet column naming rather than plain base-26 so the
  /// first 26 ids are single-letter (matches the PRD/SVG examples).
  static String _encode(int n) {
    var i = n;
    final buf = StringBuffer();
    while (true) {
      final rem = i % 26;
      buf.write(String.fromCharCode(65 + rem));
      i = (i ~/ 26) - 1;
      if (i < 0) break;
    }
    return buf.toString().split('').reversed.join();
  }
}
