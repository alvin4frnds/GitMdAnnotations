import 'dart:typed_data';

/// Commit message + writes applied atomically as one commit.
class PlannedCommit {
  const PlannedCommit({required this.message, required this.writes});
  final String message;
  final List<PlannedWrite> writes;
}

/// Sealed root of the two write variants; see `CommitPlanner` for motivation.
sealed class PlannedWrite {
  const PlannedWrite({required this.path});
  final String path;
}

class PlannedTextWrite extends PlannedWrite {
  const PlannedTextWrite({required super.path, required this.contents});
  final String contents;
}

class PlannedBinaryWrite extends PlannedWrite {
  const PlannedBinaryWrite({required super.path, required this.bytes});
  final Uint8List bytes;
}

/// Markdown annotation pair: git-diffable SVG + flattened PNG.
class MarkdownAnnotations {
  const MarkdownAnnotations({required this.svg, required this.png});
  final String svg;
  final Uint8List png;
}

/// PDF annotation set keyed by 1-based page number. Keys must match.
class PdfAnnotationSet {
  const PdfAnnotationSet({required this.svgByPage, required this.pngByPage});
  final Map<int, String> svgByPage;
  final Map<int, Uint8List> pngByPage;
}
