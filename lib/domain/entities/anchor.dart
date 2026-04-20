/// An anchor ties a stroke group to a specific region of a spec file. See
/// IMPLEMENTATION.md §2.6 and §3.4.
///
/// Sealed: exhaustive switches over [Anchor] get compile-time checks when a
/// new anchor kind is added.
sealed class Anchor {
  const Anchor({required this.sourceSha});

  /// The git blob SHA of the source file version the stroke was drawn over.
  final String sourceSha;
}

/// Anchor in a markdown source: `data-anchor-line="<lineNumber>"`.
class MarkdownAnchor extends Anchor {
  MarkdownAnchor({
    required this.lineNumber,
    required super.sourceSha,
  }) {
    if (lineNumber <= 0) {
      throw ArgumentError.value(
        lineNumber,
        'lineNumber',
        'must be > 0',
      );
    }
  }

  final int lineNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownAnchor &&
          other.lineNumber == lineNumber &&
          other.sourceSha == sourceSha;

  @override
  int get hashCode => Object.hash(lineNumber, sourceSha);

  @override
  String toString() =>
      'MarkdownAnchor(lineNumber: $lineNumber, sourceSha: $sourceSha)';
}

/// Anchor in a PDF source: `data-anchor-page` + `data-anchor-bbox`.
class PdfAnchor extends Anchor {
  PdfAnchor({
    required this.page,
    required this.bbox,
    required super.sourceSha,
  }) {
    if (page <= 0) {
      throw ArgumentError.value(page, 'page', 'must be > 0');
    }
  }

  final int page;
  final Rect bbox;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfAnchor &&
          other.page == page &&
          other.bbox == bbox &&
          other.sourceSha == sourceSha;

  @override
  int get hashCode => Object.hash(page, bbox, sourceSha);

  @override
  String toString() =>
      'PdfAnchor(page: $page, bbox: $bbox, sourceSha: $sourceSha)';
}

/// Axis-aligned bounding box in PDF page coordinates. Defined here (not
/// imported from `dart:ui`) so the domain layer stays Flutter-free.
class Rect {
  const Rect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rect &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Rect($left, $top, $right, $bottom)';
}
