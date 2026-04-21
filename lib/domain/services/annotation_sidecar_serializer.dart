import 'dart:convert';

import '../entities/anchor.dart';
import '../entities/stroke.dart';
import '../entities/stroke_group.dart';
import 'svg_serializer.dart' show SvgSource;

/// Emits `03-annotations.json` — a format-agnostic, parse-once anchor +
/// stroke store that sits alongside the SVG / PNG / PDF artifacts.
///
/// Why JSON in addition to SVG: the SVG hard-codes its coordinates into
/// `<path d="…">` strings and spreads anchor metadata across attributes,
/// which is fine for rendering but annoying to parse from external
/// tooling. The JSON sidecar exposes the same information as plain
/// objects with named fields so downstream code (future desktop
/// watcher, analytics, anything that wants to aggregate strokes) can
/// read a single file without an XML parser.
///
/// Keeping the SVG around during transition: the user chose to keep
/// writing all three legacy artifacts (svg + png) plus the new PDF +
/// JSON — so this service never replaces anything, it just adds the
/// fourth write. Once external tooling is confirmed PDF/JSON-ready, the
/// SVG/PNG writes can be retired.
class AnnotationSidecarSerializer {
  const AnnotationSidecarSerializer({
    required this.canonicalWidth,
  });

  /// The canonical logical width at which strokes were captured. Stored
  /// alongside the stroke coords so any downstream consumer knows the
  /// coordinate space without having to cross-reference widget code.
  final double canonicalWidth;

  /// Serializes [groups] anchored to [source] into a pretty-printed
  /// UTF-8 JSON string. Trailing newline for POSIX-friendly file
  /// behavior and to reduce noise in git diffs.
  String serialize(List<StrokeGroup> groups, SvgSource source) {
    final payload = <String, Object>{
      'schemaVersion': 1,
      'sourceFile': source.sourceFile,
      'sourceSha': source.sourceSha,
      'canonicalWidth': canonicalWidth,
      'groups': groups.map(_groupToJson).toList(),
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  Map<String, Object> _groupToJson(StrokeGroup g) => {
        'id': g.id,
        'anchor': _anchorToJson(g.anchor),
        'timestamp': _formatTimestamp(g.timestamp),
        'strokes': g.strokes.map(_strokeToJson).toList(),
      };

  Map<String, Object> _anchorToJson(Anchor a) => switch (a) {
        MarkdownAnchor(:final lineNumber, :final sourceSha) => {
            'kind': 'markdown',
            'lineNumber': lineNumber,
            'sourceSha': sourceSha,
          },
        PdfAnchor(:final page, :final bbox, :final sourceSha) => {
            'kind': 'pdf',
            'page': page,
            'bbox': {
              'left': bbox.left,
              'top': bbox.top,
              'right': bbox.right,
              'bottom': bbox.bottom,
            },
            'sourceSha': sourceSha,
          },
      };

  Map<String, Object> _strokeToJson(Stroke s) => {
        'color': s.color.toUpperCase(),
        'strokeWidth': s.strokeWidth,
        'opacity': s.opacity,
        'points': s.points.map(_pointToJson).toList(),
      };

  Map<String, double> _pointToJson(StrokePoint p) => {
        'x': p.x,
        'y': p.y,
        'pressure': p.pressure,
      };

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
}
