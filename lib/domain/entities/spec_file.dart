import 'source_kind.dart';

/// The loaded content of a spec file on disk along with the git blob SHA of
/// the snapshot reviewed.
///
/// See IMPLEMENTATION.md §2.6 and §3.4. [sha] must be non-empty — this is the
/// `data-source-sha` embedded into the annotation SVG so desktop Claude can
/// re-anchor strokes against the exact version reviewed.
class SpecFile {
  SpecFile({
    required this.path,
    required this.sha,
    required this.contents,
    required this.sourceKind,
  }) {
    if (sha.isEmpty) {
      throw ArgumentError.value(sha, 'sha', 'must be non-empty');
    }
  }

  final String path;
  final String sha;
  final String contents;
  final SourceKind sourceKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecFile &&
          other.path == path &&
          other.sha == sha &&
          other.contents == contents &&
          other.sourceKind == sourceKind;

  @override
  int get hashCode => Object.hash(path, sha, contents, sourceKind);

  @override
  String toString() =>
      'SpecFile(path: $path, sha: $sha, sourceKind: ${sourceKind.name})';
}
