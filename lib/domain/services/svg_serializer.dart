import '../entities/anchor.dart';
import '../entities/stroke.dart';
import '../entities/stroke_group.dart';

/// Identifies the source spec a set of stroke groups was drawn over.
/// Written into the SVG root as `data-source-file` and `data-source-sha`
/// (IMPLEMENTATION.md §3.4).
class SvgSource {
  const SvgSource({required this.sourceFile, required this.sourceSha});

  final String sourceFile;
  final String sourceSha;
}

/// Serializes a list of [StrokeGroup]s into the canonical SVG form defined in
/// IMPLEMENTATION.md §3.4. Pure domain service — zero Flutter / `dart:io`.
class SvgSerializer {
  const SvgSerializer();

  /// Serializes [groups] anchored to [source]. Groups are emitted in the order
  /// provided. Timestamps are formatted ISO-8601 UTC (`…Z`). Output uses LF
  /// line endings and a trailing newline.
  String serialize(List<StrokeGroup> groups, SvgSource source) {
    final buf = StringBuffer();
    final file = _escapeAttr(source.sourceFile);
    final sha = _escapeAttr(source.sourceSha);
    buf.write(
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' data-source-file="$file"'
      ' data-source-sha="$sha"',
    );
    if (groups.isEmpty) {
      buf.write('></svg>\n');
      return buf.toString();
    }
    buf.write('>\n');
    for (final g in groups) {
      _writeGroup(buf, g);
    }
    buf.write('</svg>\n');
    return buf.toString();
  }

  void _writeGroup(StringBuffer buf, StrokeGroup g) {
    final anchorAttrs = _anchorAttrs(g.anchor);
    final ts = _formatTimestamp(g.timestamp);
    buf.write(
      '  <g id="${g.id}" $anchorAttrs data-timestamp="$ts">\n',
    );
    for (final s in g.strokes) {
      _writeStroke(buf, s);
    }
    buf.write('  </g>\n');
  }

  void _writeStroke(StringBuffer buf, Stroke s) {
    final d = _pathData(s.points);
    final stroke = s.color.toUpperCase();
    final width = _formatNumber(s.strokeWidth);
    buf.write(
      '    <path d="$d" stroke="$stroke"'
      ' stroke-width="$width" opacity="0.9"/>\n',
    );
  }

  String _pathData(List<StrokePoint> points) {
    if (points.isEmpty) return '';
    final buf = StringBuffer();
    buf.write('M ${_formatNumber(points.first.x)},'
        '${_formatNumber(points.first.y)}');
    for (var i = 1; i < points.length; i++) {
      buf.write(' L ${_formatNumber(points[i].x)},'
          '${_formatNumber(points[i].y)}');
    }
    return buf.toString();
  }

  String _anchorAttrs(Anchor a) {
    switch (a) {
      case MarkdownAnchor(:final lineNumber):
        return 'data-anchor-line="$lineNumber"';
      case PdfAnchor(:final page, :final bbox):
        final b = '${_formatNumber(bbox.left)},'
            '${_formatNumber(bbox.top)},'
            '${_formatNumber(bbox.right)},'
            '${_formatNumber(bbox.bottom)}';
        return 'data-anchor-page="$page" data-anchor-bbox="$b"';
    }
  }
}

String _formatNumber(double n) {
  if (n == n.truncateToDouble() && n.isFinite) {
    return n.toInt().toString();
  }
  return n.toString();
}

String _escapeAttr(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _formatTimestamp(DateTime dt) {
  final u = dt.toUtc();
  final y = u.year.toString().padLeft(4, '0');
  final mo = u.month.toString().padLeft(2, '0');
  final d = u.day.toString().padLeft(2, '0');
  final h = u.hour.toString().padLeft(2, '0');
  final mi = u.minute.toString().padLeft(2, '0');
  final s = u.second.toString().padLeft(2, '0');
  return '$y-$mo-${d}T$h:$mi:${s}Z';
}
