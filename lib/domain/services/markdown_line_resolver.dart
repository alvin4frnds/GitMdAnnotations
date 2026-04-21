/// Maps a stroke's content-local Y coordinate to an approximate source-line
/// number in the rendered markdown spec.
///
/// Proportional: `lineNumber ≈ sampleY / contentHeight × totalLines`, clamped
/// to `[1, totalLines]`. Assumes uniform vertical distribution of lines —
/// headings take more pixels than body lines, so this is paragraph-level
/// accurate, not exact. For the canonical-width pipeline
/// (`kAnnotatedContentWidth = 900`) that's enough to place a stroke in the
/// right section of the spec, which is what the desktop side uses anchors
/// for.
///
/// An exact mapping would need per-block RenderBox measurement during build;
/// future work, see IMPLEMENTATION.md §4.4.
int resolveMarkdownLine({
  required double sampleY,
  required double contentHeight,
  required int totalLines,
}) {
  if (totalLines < 1) {
    throw ArgumentError.value(totalLines, 'totalLines', 'must be >= 1');
  }
  if (totalLines == 1) return 1;
  if (contentHeight <= 0 || !contentHeight.isFinite) return 1;
  if (!sampleY.isFinite) return 1;
  final ratio = (sampleY / contentHeight).clamp(0.0, 1.0);
  final line = (ratio * totalLines).floor() + 1;
  return line.clamp(1, totalLines);
}

/// Counts source lines in a markdown string, matching the 1-indexed line
/// numbering that `MarkdownAnchor.lineNumber` uses.
///
/// Empty string → 1 (a file with no content still has "line 1"). A trailing
/// newline does not add a phantom empty line.
int countMarkdownLines(String text) {
  if (text.isEmpty) return 1;
  var count = 1;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
  }
  if (text.codeUnitAt(text.length - 1) == 0x0A) count--;
  return count < 1 ? 1 : count;
}
