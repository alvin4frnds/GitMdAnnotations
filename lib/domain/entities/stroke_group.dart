import 'anchor.dart';
import 'stroke.dart';

/// A `<g>` element in the annotation SVG — one or more strokes sharing a
/// single [anchor] and [timestamp] (IMPLEMENTATION.md §3.4).
///
/// [timestamp] is stored as-is; serialization to ISO-8601 UTC (the format
/// written into `data-timestamp`) is a concern of the SVG serializer, not of
/// this value object.
class StrokeGroup {
  StrokeGroup({
    required this.id,
    required this.anchor,
    required this.timestamp,
    required this.strokes,
  }) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be non-empty');
    }
  }

  final String id;
  final Anchor anchor;
  final DateTime timestamp;
  final List<Stroke> strokes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StrokeGroup) return false;
    if (other.id != id) return false;
    if (other.anchor != anchor) return false;
    if (other.timestamp != timestamp) return false;
    if (other.strokes.length != strokes.length) return false;
    for (var i = 0; i < strokes.length; i++) {
      if (other.strokes[i] != strokes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(id, anchor, timestamp, Object.hashAll(strokes));

  @override
  String toString() =>
      'StrokeGroup(id: $id, anchor: $anchor, timestamp: $timestamp, strokes: ${strokes.length})';
}
