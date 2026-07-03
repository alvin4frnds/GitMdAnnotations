import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/anchor.dart';
import 'package:gitmdscribe/domain/entities/stroke.dart';
import 'package:gitmdscribe/domain/entities/stroke_group.dart';
import 'package:gitmdscribe/ui/widgets/ink_overlay/ink_painting.dart';

/// The shared paint function extracted from `InkOverlayPainter` so both the
/// on-screen painter and the infra PNG flattener can produce byte-identical
/// output. This test file pins that the pure function exists and renders
/// without throwing on the same shapes the painter already handles.
MarkdownAnchor _anchor() =>
    MarkdownAnchor(lineNumber: 47, sourceSha: 'a3f91c');

Stroke _stroke(
  List<Offset> pts, {
  String color = '#DC2626',
  double width = 2.1,
}) {
  return Stroke(
    points: pts
        .map((p) => StrokePoint(x: p.dx, y: p.dy, pressure: 0.5))
        .toList(growable: false),
    color: color,
    strokeWidth: width,
  );
}

StrokeGroup _group(List<Stroke> strokes, {String id = 'g1'}) {
  return StrokeGroup(
    id: id,
    anchor: _anchor(),
    timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
    strokes: strokes,
  );
}

Canvas _canvasOn(ui.PictureRecorder r) => Canvas(r);

void main() {
  group('paintStrokeGroups (pure)', () {
    test('runs without throwing on empty groups + empty active stroke', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: const [],
        activeStrokePoints: const [],
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });

    test('runs without throwing on a single committed multi-point stroke', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: [
          _group([
            _stroke(const [Offset(10, 10), Offset(20, 20), Offset(30, 25)]),
          ]),
        ],
        activeStrokePoints: const [],
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });

    test('runs without throwing on a single-point committed stroke', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: [
          _group([_stroke(const [Offset(10, 10)])]),
        ],
        activeStrokePoints: const [],
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });

    test('skips empty strokes inside a committed group', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: [
          _group([_stroke(const [])]),
        ],
        activeStrokePoints: const [],
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });

    test('renders a coarse closed loop (many-point stroke) without throwing '
        'via the actual-stroke polyline path (BUG-1)', () {
      // A sparsely-sampled circle is the case that exposed the facetted
      // "rough lines" bug. It now renders as a stroked polyline through the
      // real points (full width, round joins) rather than a resampled
      // perfect_freehand outline. Guards that path from regressing to a
      // crash on the closed-loop / repeated-endpoint handling.
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      const cx = 60.0, cy = 60.0, r = 40.0;
      final pts = [
        for (var i = 0; i <= 12; i++)
          Offset(cx + r * math.cos(i * math.pi / 6),
              cy + r * math.sin(i * math.pi / 6)),
      ];
      paintStrokeGroups(
        canvas,
        groups: [
          _group([_stroke(pts)]),
        ],
        activeStrokePoints: pts,
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 3.5,
      );
      recorder.endRecording().dispose();
    });

    test('runs without throwing on a 2-point active stroke', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: const [],
        activeStrokePoints: const [Offset(5, 5), Offset(15, 15)],
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });

    test('runs without throwing on a 1-point active stroke', () {
      final recorder = ui.PictureRecorder();
      final canvas = _canvasOn(recorder);
      paintStrokeGroups(
        canvas,
        groups: const [],
        activeStrokePoints: const [Offset(5, 5)],
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      recorder.endRecording().dispose();
    });
  });
}
