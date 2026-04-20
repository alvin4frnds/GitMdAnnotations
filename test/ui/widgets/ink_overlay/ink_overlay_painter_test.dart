import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/ink_overlay_painter.dart';

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

/// Records a paint call onto a [PictureRecorder] + [ui.Canvas]; returns
/// normally iff `paint` completes without throwing.
void _smokePaint(InkOverlayPainter painter, {Size size = const Size(800, 600)}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}

void main() {
  group('InkOverlayPainter.shouldRepaint', () {
    test('returns true when groups list length differs', () {
      final active = ValueNotifier<List<Offset>>(const []);
      final before = InkOverlayPainter(
        groups: const [],
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      final after = InkOverlayPainter(
        groups: [_group([_stroke(const [Offset(0, 0)])])],
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(after.shouldRepaint(before), isTrue);
    });

    test('returns true when activeStrokeColor differs', () {
      final active = ValueNotifier<List<Offset>>(const []);
      final before = InkOverlayPainter(
        groups: const [],
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      final after = InkOverlayPainter(
        groups: const [],
        activeStroke: active,
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      expect(after.shouldRepaint(before), isTrue);
    });

    test('returns true when activeStrokeWidth differs', () {
      final active = ValueNotifier<List<Offset>>(const []);
      final before = InkOverlayPainter(
        groups: const [],
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      final after = InkOverlayPainter(
        groups: const [],
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 4.0,
      );
      expect(after.shouldRepaint(before), isTrue);
    });

    test('returns false when nothing material changes (same ref)', () {
      final active = ValueNotifier<List<Offset>>(const []);
      final groups = [_group([_stroke(const [Offset(0, 0)])])];
      final before = InkOverlayPainter(
        groups: groups,
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      final after = InkOverlayPainter(
        groups: groups,
        activeStroke: active,
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(after.shouldRepaint(before), isFalse);
    });
  });

  group('InkOverlayPainter.paint', () {
    test('does not throw on empty groups + empty active stroke', () {
      final painter = InkOverlayPainter(
        groups: const [],
        activeStroke: ValueNotifier<List<Offset>>(const []),
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on a group with an empty stroke', () {
      final painter = InkOverlayPainter(
        groups: [_group([_stroke(const [])])],
        activeStroke: ValueNotifier<List<Offset>>(const []),
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on a single-point stroke', () {
      final painter = InkOverlayPainter(
        groups: [_group([_stroke(const [Offset(10, 10)])])],
        activeStroke: ValueNotifier<List<Offset>>(const []),
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on a normal multi-point stroke', () {
      final painter = InkOverlayPainter(
        groups: [
          _group([
            _stroke(const [
              Offset(10, 10),
              Offset(20, 20),
              Offset(30, 25),
              Offset(40, 15),
            ]),
          ]),
        ],
        activeStroke: ValueNotifier<List<Offset>>(const []),
        activeStrokeColor: const Color(0xFF000000),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on 1-point active stroke', () {
      final painter = InkOverlayPainter(
        groups: const [],
        activeStroke: ValueNotifier<List<Offset>>(const [Offset(5, 5)]),
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on 2-point active stroke', () {
      final painter = InkOverlayPainter(
        groups: const [],
        activeStroke: ValueNotifier<List<Offset>>(
          const [Offset(5, 5), Offset(15, 15)],
        ),
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw on many-point active stroke', () {
      final points = List<Offset>.generate(
        100,
        (i) => Offset(i.toDouble(), (i * 2).toDouble()),
      );
      final painter = InkOverlayPainter(
        groups: const [],
        activeStroke: ValueNotifier<List<Offset>>(points),
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.0,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });

    test('does not throw when committed groups + active stroke combine', () {
      final painter = InkOverlayPainter(
        groups: [
          _group([
            _stroke(const [Offset(10, 10), Offset(20, 20)]),
            _stroke(
              const [Offset(30, 30), Offset(40, 40)],
              color: '#2563EB',
              width: 1.4,
            ),
          ]),
        ],
        activeStroke: ValueNotifier<List<Offset>>(
          const [Offset(50, 50), Offset(60, 60), Offset(70, 70)],
        ),
        activeStrokeColor: const Color(0xFFDC2626),
        activeStrokeWidth: 2.4,
      );
      expect(() => _smokePaint(painter), returnsNormally);
    });
  });
}
